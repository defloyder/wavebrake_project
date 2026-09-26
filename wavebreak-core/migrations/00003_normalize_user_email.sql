-- +goose Up
do $$
declare
    duplicate_groups integer;
begin
    select count(*)
    into duplicate_groups
    from (
        select lower(btrim(email))
        from users
        where email is not null
        group by lower(btrim(email))
        having count(*) > 1
    ) duplicates;

    if duplicate_groups > 0 then
        raise exception 'cannot normalize users.email: % duplicate group(s) require manual resolution', duplicate_groups;
    end if;
end $$;

update users
set email = lower(btrim(email)), updated_at = now()
where email is not null
  and email is distinct from lower(btrim(email));

alter table users drop constraint if exists users_email_normalized_check;
alter table users add constraint users_email_normalized_check
    check (email is null or (email <> '' and email = lower(btrim(email))));

create unique index users_email_normalized_unique_idx
    on users (lower(btrim(email)))
    where email is not null;

-- +goose Down
drop index if exists users_email_normalized_unique_idx;
alter table users drop constraint if exists users_email_normalized_check;
