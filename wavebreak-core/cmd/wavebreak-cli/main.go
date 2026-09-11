package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"syscall"
	"time"

	"golang.org/x/term"

	"wavebreak-core/internal/config"
	"wavebreak-core/internal/database"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if len(os.Args) < 3 {
		usage()
		os.Exit(2)
	}

	cfg, err := config.Load()
	if err != nil {
		log.Error("load config", "error", err)
		os.Exit(1)
	}
	ctx := context.Background()
	db, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Error("open database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	st := store.New(db)
	switch os.Args[1] + " " + os.Args[2] {
	case "admin create":
		if err := adminCreate(ctx, st, os.Args[3:]); err != nil {
			log.Error("admin create failed", "error", err)
			os.Exit(1)
		}
	case "admin reset-password":
		if err := adminResetPassword(ctx, st, os.Args[3:]); err != nil {
			log.Error("admin reset-password failed", "error", err)
			os.Exit(1)
		}
	case "node token":
		if err := nodeToken(ctx, st, os.Args[3:]); err != nil {
			log.Error("node token failed", "error", err)
			os.Exit(1)
		}
	default:
		usage()
		os.Exit(2)
	}
}

func adminCreate(ctx context.Context, st *store.Store, args []string) error {
	fs := flag.NewFlagSet("admin create", flag.ExitOnError)
	email := fs.String("email", "", "admin email")
	password := fs.String("password", "", "admin password; omit for secure prompt")
	role := fs.String("role", "superadmin", "support, admin, or superadmin")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *email == "" {
		*email = promptLine("Email: ")
	}
	if *password == "" {
		var err error
		*password, err = promptPasswordTwice()
		if err != nil {
			return err
		}
	}
	if *role != "support" && *role != "admin" && *role != "superadmin" {
		return fmt.Errorf("role must be support, admin, or superadmin")
	}
	hash, err := security.HashPassword(*password)
	if err != nil {
		return err
	}
	user, err := st.CreateUserWithRole(ctx, strings.ToLower(strings.TrimSpace(*email)), hash, *role)
	if err != nil {
		return err
	}
	userID := user.ID
	if err := st.WriteAuditEvent(ctx, &userID, "admin.created", "user", &userID, map[string]any{"role": *role}); err != nil {
		return err
	}
	fmt.Printf("created %s %s\n", *role, user.Email)
	return nil
}

func adminResetPassword(ctx context.Context, st *store.Store, args []string) error {
	fs := flag.NewFlagSet("admin reset-password", flag.ExitOnError)
	email := fs.String("email", "", "admin email")
	password := fs.String("password", "", "new password; omit for secure prompt")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *email == "" {
		*email = promptLine("Email: ")
	}
	if *password == "" {
		var err error
		*password, err = promptPasswordTwice()
		if err != nil {
			return err
		}
	}
	hash, err := security.HashPassword(*password)
	if err != nil {
		return err
	}
	emailValue := strings.ToLower(strings.TrimSpace(*email))
	if err := st.SetUserPassword(ctx, emailValue, hash); err != nil {
		return err
	}
	if err := st.WriteAuditEvent(ctx, nil, "admin.password_reset", "user", nil, map[string]any{"email": emailValue}); err != nil {
		return err
	}
	fmt.Printf("password reset for %s\n", emailValue)
	return nil
}

func nodeToken(ctx context.Context, st *store.Store, args []string) error {
	fs := flag.NewFlagSet("node token", flag.ExitOnError)
	region := fs.String("region", "", "node region")
	ttl := fs.Duration("ttl", 24*time.Hour, "token ttl")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *region == "" {
		*region = promptLine("Region: ")
	}
	token, err := security.RandomToken(32)
	if err != nil {
		return err
	}
	if err := st.CreateNodeEnrollmentToken(ctx, strings.TrimSpace(*region), token, time.Now().UTC().Add(*ttl)); err != nil {
		return err
	}
	fmt.Printf("node enrollment token: %s\n", token)
	return nil
}

func promptLine(label string) string {
	fmt.Print(label)
	value, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	return strings.TrimSpace(value)
}

func promptPasswordTwice() (string, error) {
	fmt.Print("Password: ")
	first, err := term.ReadPassword(int(syscall.Stdin))
	fmt.Println()
	if err != nil {
		return "", err
	}
	fmt.Print("Confirm password: ")
	second, err := term.ReadPassword(int(syscall.Stdin))
	fmt.Println()
	if err != nil {
		return "", err
	}
	if string(first) != string(second) {
		return "", fmt.Errorf("passwords do not match")
	}
	if len(first) < 12 {
		return "", fmt.Errorf("password must be at least 12 characters")
	}
	return string(first), nil
}

func usage() {
	fmt.Println("usage:")
	fmt.Println("  wavebreak-cli admin create [--email EMAIL] [--role superadmin] [--password PASSWORD]")
	fmt.Println("  wavebreak-cli admin reset-password [--email EMAIL] [--password PASSWORD]")
	fmt.Println("  wavebreak-cli node token [--region REGION] [--ttl 24h]")
}
