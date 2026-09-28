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

	"wavebreak-core/internal/accounts"
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
	case "node mirror":
		if err := nodeMirror(ctx, st, os.Args[3:]); err != nil {
			log.Error("node mirror failed", "error", err)
			os.Exit(1)
		}
	case "subscriptions lifecycle":
		if err := subscriptionsLifecycle(ctx, st, cfg.Accounts.SubscriptionGrace, os.Args[3:]); err != nil {
			log.Error("subscriptions lifecycle failed", "error", err)
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

// nodeMirror makes a second location (e.g. RU-MSK-01) serve another node's
// accounts (e.g. TR-PILOT-01), with its own public connection parameters:
// a JSON object of config.VLESSConfig fields (PublicHost, PublicPort,
// RealityPublicKey, RealityShortID, RealityServerName, PublishDirect,
// DirectTLSHost, DirectTLSPort, DirectTLSPath, HysteriaHost, HysteriaPort, ...).
func nodeMirror(ctx context.Context, st *store.Store, args []string) error {
	fs := flag.NewFlagSet("node mirror", flag.ExitOnError)
	node := fs.String("node", "", "code of the mirror node")
	of := fs.String("of", "", "code of the node whose accounts it serves")
	configPath := fs.String("config", "", "public connection parameters (JSON file)")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *node == "" || *of == "" || *configPath == "" {
		return fmt.Errorf("--node, --of and --config are required")
	}
	raw, err := os.ReadFile(*configPath)
	if err != nil {
		return err
	}
	revision, err := st.LinkMirrorNode(ctx, *node, *of, raw)
	if err != nil {
		return err
	}
	fmt.Printf("%s now serves the accounts of %s (desired-state revision %d)\n", *node, *of, revision)
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
	fmt.Println("  wavebreak-cli node mirror --node CODE --of CODE --config FILE.json")
	fmt.Println("  wavebreak-cli subscriptions lifecycle [--dry-run]")
}

// subscriptionsLifecycle runs the subscription lifecycle once (what the
// worker does every minute). --dry-run only lists what would change.
func subscriptionsLifecycle(ctx context.Context, st *store.Store, grace time.Duration, args []string) error {
	fs := flag.NewFlagSet("subscriptions lifecycle", flag.ContinueOnError)
	dryRun := fs.Bool("dry-run", false, "only list the subscriptions that would change")
	if err := fs.Parse(args); err != nil {
		return err
	}
	repo := st.Accounts()
	if *dryRun {
		now := time.Now().UTC()
		due, err := repo.DueForGrace(ctx, now)
		if err != nil {
			return err
		}
		for _, c := range due {
			fmt.Printf("past_due  subscription=%s user=%s reason=%s\n", c.SubscriptionID, c.UserID, c.Reason)
		}
		expiring, err := repo.DueForExpiry(ctx, now.Add(-grace))
		if err != nil {
			return err
		}
		for _, c := range expiring {
			fmt.Printf("expire    subscription=%s user=%s reason=%s\n", c.SubscriptionID, c.UserID, c.Reason)
		}
		fmt.Printf("dry run: %d would go past_due, %d would expire (past_due ones may also expire on the same run)\n", len(due), len(expiring))
		return nil
	}
	report, err := accounts.NewSubscriptionLifecycleService(repo, repo, grace).Run(ctx)
	fmt.Printf("past_due=%d expired=%d\n", report.PastDue, report.Expired)
	return err
}
