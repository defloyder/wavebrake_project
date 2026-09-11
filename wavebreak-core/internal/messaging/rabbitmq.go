package messaging

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

const (
	EventsExchange     = "wavebreak.events"
	JobsExchange       = "wavebreak.jobs"
	DeadLetterExchange = "wavebreak.deadletter"
)

type Publisher struct {
	conn     *amqp.Connection
	ch       *amqp.Channel
	confirms <-chan amqp.Confirmation
}

type Event struct {
	ID          string          `json:"id"`
	Type        string          `json:"type"`
	AggregateID string          `json:"aggregate_id"`
	Payload     json.RawMessage `json:"payload"`
	CreatedAt   time.Time       `json:"created_at"`
}

func Connect(url string) (*Publisher, error) {
	conn, err := amqp.Dial(url)
	if err != nil {
		return nil, fmt.Errorf("dial rabbitmq: %w", err)
	}
	ch, err := conn.Channel()
	if err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("open rabbitmq channel: %w", err)
	}
	p := &Publisher{conn: conn, ch: ch}
	if err := ch.Confirm(false); err != nil {
		_ = p.Close()
		return nil, fmt.Errorf("enable rabbitmq publisher confirms: %w", err)
	}
	p.confirms = ch.NotifyPublish(make(chan amqp.Confirmation, 1))
	if err := p.DeclareTopology(); err != nil {
		_ = p.Close()
		return nil, err
	}
	return p, nil
}

func (p *Publisher) Close() error {
	if p.ch != nil {
		_ = p.ch.Close()
	}
	if p.conn != nil {
		return p.conn.Close()
	}
	return nil
}

func (p *Publisher) DeclareTopology() error {
	for _, name := range []string{EventsExchange, JobsExchange, DeadLetterExchange} {
		if err := p.ch.ExchangeDeclare(name, "topic", true, false, false, false, nil); err != nil {
			return fmt.Errorf("declare exchange %s: %w", name, err)
		}
	}

	queues := []struct {
		Name       string
		Binding    string
		Exchange   string
		DeadLetter string
	}{
		{"wavebreak.jobs.notification", "notification.*", JobsExchange, "wavebreak.deadletter.notification"},
		{"wavebreak.jobs.subscription", "subscription.*", EventsExchange, "wavebreak.deadletter.subscription"},
		{"wavebreak.jobs.node", "node.*", EventsExchange, "wavebreak.deadletter.node"},
		{"wavebreak.jobs.access", "access.*", EventsExchange, "wavebreak.deadletter.access"},
	}
	for _, q := range queues {
		args := amqp.Table{
			"x-dead-letter-exchange":    DeadLetterExchange,
			"x-dead-letter-routing-key": q.DeadLetter,
		}
		if _, err := p.ch.QueueDeclare(q.Name, true, false, false, false, args); err != nil {
			return fmt.Errorf("declare queue %s: %w", q.Name, err)
		}
		if err := p.ch.QueueBind(q.Name, q.Binding, q.Exchange, false, nil); err != nil {
			return fmt.Errorf("bind queue %s: %w", q.Name, err)
		}
		if _, err := p.ch.QueueDeclare(q.DeadLetter, true, false, false, false, nil); err != nil {
			return fmt.Errorf("declare dlq %s: %w", q.DeadLetter, err)
		}
		if err := p.ch.QueueBind(q.DeadLetter, q.DeadLetter, DeadLetterExchange, false, nil); err != nil {
			return fmt.Errorf("bind dlq %s: %w", q.DeadLetter, err)
		}
	}
	return nil
}

func (p *Publisher) PublishEvent(ctx context.Context, event Event) error {
	body, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("marshal event: %w", err)
	}
	if err := p.ch.PublishWithContext(ctx, EventsExchange, event.Type, false, false, amqp.Publishing{
		ContentType:  "application/json",
		DeliveryMode: amqp.Persistent,
		MessageId:    event.ID,
		Timestamp:    time.Now().UTC(),
		Body:         body,
	}); err != nil {
		return err
	}
	select {
	case confirm := <-p.confirms:
		if !confirm.Ack {
			return fmt.Errorf("rabbitmq publish was not acknowledged")
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
