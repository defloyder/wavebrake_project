-- +goose Up
-- Plans' device limits were raised after some subscriptions were bought,
-- and those subscriptions kept the old (lower) snapshot: a Flagship buyer
-- was limited to 1 device instead of 10. Raise live subscriptions' snapshot
-- to their plan's current limit; never lower it. Overrides are untouched.
update subscriptions s
set device_limit_snapshot = p.device_limit, updated_at = now()
from plans p
where p.id = s.plan_id
  and s.status in ('pending', 'trialing', 'active', 'past_due', 'suspended')
  and (s.device_limit_snapshot is null or s.device_limit_snapshot < p.device_limit);

-- +goose Down
-- Data fix; the old snapshots are not restored.
select 1;
