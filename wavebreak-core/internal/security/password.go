package security

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/bcrypt"
)

const (
	argonMemory      = 64 * 1024
	argonIterations  = 3
	argonParallelism = 2
	argonSaltLength  = 16
	argonKeyLength   = 32
)

var ErrInvalidHash = errors.New("invalid password hash")

func HashPassword(password string) (string, error) {
	salt := make([]byte, argonSaltLength)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("generate password salt: %w", err)
	}
	key := argon2.IDKey([]byte(password), salt, argonIterations, argonMemory, argonParallelism, argonKeyLength)
	return fmt.Sprintf("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s",
		argonMemory,
		argonIterations,
		argonParallelism,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	), nil
}

func VerifyPassword(password, encoded string) (bool, error) {
	if strings.HasPrefix(encoded, "$2a$") || strings.HasPrefix(encoded, "$2b$") || strings.HasPrefix(encoded, "$2y$") {
		err := bcrypt.CompareHashAndPassword([]byte(encoded), []byte(password))
		return err == nil, nil
	}

	params, salt, expected, err := decodeArgon2id(encoded)
	if err != nil {
		return false, err
	}
	actual := argon2.IDKey([]byte(password), salt, params.iterations, params.memory, params.parallelism, uint32(len(expected)))
	return subtle.ConstantTimeCompare(actual, expected) == 1, nil
}

type argonParams struct {
	memory      uint32
	iterations  uint32
	parallelism uint8
}

func decodeArgon2id(encoded string) (argonParams, []byte, []byte, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" || parts[2] != "v=19" {
		return argonParams{}, nil, nil, ErrInvalidHash
	}
	values := strings.Split(parts[3], ",")
	if len(values) != 3 {
		return argonParams{}, nil, nil, ErrInvalidHash
	}
	var params argonParams
	for _, value := range values {
		key, raw, ok := strings.Cut(value, "=")
		if !ok {
			return argonParams{}, nil, nil, ErrInvalidHash
		}
		parsed, err := strconv.ParseUint(raw, 10, 32)
		if err != nil {
			return argonParams{}, nil, nil, ErrInvalidHash
		}
		switch key {
		case "m":
			params.memory = uint32(parsed)
		case "t":
			params.iterations = uint32(parsed)
		case "p":
			if parsed > 255 {
				return argonParams{}, nil, nil, ErrInvalidHash
			}
			params.parallelism = uint8(parsed)
		default:
			return argonParams{}, nil, nil, ErrInvalidHash
		}
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return argonParams{}, nil, nil, ErrInvalidHash
	}
	hash, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return argonParams{}, nil, nil, ErrInvalidHash
	}
	if params.memory == 0 || params.iterations == 0 || params.parallelism == 0 || len(salt) == 0 || len(hash) == 0 {
		return argonParams{}, nil, nil, ErrInvalidHash
	}
	return params, salt, hash, nil
}
