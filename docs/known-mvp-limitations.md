# Known MVP Limitations

- Laravel apps are Blade-based rather than Inertia/Vue.
- Admin uses Core role checks for `support`/`admin`/`superadmin`, but does not yet include real MFA enrollment/challenge UI.
- Billing adapters are represented by subscription/payment schema, not real provider integrations.
- Promo/coupon flows are still schema/API backlog.
- Node agent enrolls, heartbeats, fetches desired state, ACKs/fails revisions, and uses a runtime adapter boundary, but the current adapter is a no-op and does not yet apply real VPN/proxy protocol configuration.
- OpenTelemetry code hooks are represented by infrastructure and metrics; full distributed tracing instrumentation is still next.
- Grafana provisioning includes the first overview dashboard; the full dashboard suite should be expanded from the provided metrics.
- Composer installation on Windows can fail on packages containing reserved filenames such as `nul.env`; use WSL/Linux or authenticated dist downloads for reliable Laravel vendor installation.
