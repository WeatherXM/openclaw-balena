# OpenClaw on Balena (MOVED)

> ⚠️ **This repository has moved.** The active, up-to-date version is now maintained at [ClawQueue/openclaw-balena](https://github.com/ClawQueue/openclaw-balena). Please use that repository instead and update your remotes.
>
> This repository is archived and read-only.

Run [OpenClaw](https://github.com/openclaw/openclaw) on a Raspberry Pi 4/5 via [balenaCloud](https://balena.io). The repo provides a small Balena stack with OTA updates, rollbackable OpenClaw version snapshots, persistent config/data, and HTTPS access through HAProxy.

[![Deploy with balena](https://www.balena.io/deploy.png)](https://dashboard.balena-cloud.com/deploy?repoUrl=https://github.com/ClawQueue/openclaw-balena)

## Goal

This project is optimized for a practical appliance-style install:

- Push once with Balena.
- Open the Control UI from LAN or the Balena public URL.
- Run `openclaw onboard` / `openclaw configure` manually when you want to add providers or change OpenClaw config.
- Upgrade or roll back OpenClaw by changing one Balena device variable.

The startup script deliberately owns only Balena-specific gateway plumbing: auth token, Control UI origins, active version, and active home/config paths. It writes the persisted gateway token into the active config so Balena terminal commands such as `openclaw onboard` work without inheriting the gateway process environment. Provider/model config remains OpenClaw-managed.

## Why This Approach

- **Single-click deployment:** use the Balena deploy button or `balena push` to provision the whole stack: OpenClaw gateway, HAProxy, persistent volumes, and public/LAN web access.
- **On-demand OpenClaw upgrades:** set `OPENCLAW_VERSION` to the release you want and restart. No reflashing, no manual npm work on the Pi.
- **Rollbackable version snapshots:** each version keeps its own OpenClaw binary, config, home data, memories, skills, and plugins under `/data/openclaw/versions/<version>/`. If an install fails, startup falls back to the previous working version. To roll back later, set `OPENCLAW_VERSION` to any retained version.
- **Keep as many rollback points as you want:** set `OPENCLAW_KEEP_VERSIONS` to the number of snapshots to retain. Higher values use more disk but give you a deeper rollback history.
- **Gateway access that survives purges and restarts:** startup ignores empty/placeholder tokens, generates a real token when needed, stores it in `/data/openclaw/gateway.token`, and keeps the active config aligned for both the web UI and Balena terminal commands.
- **Manual OpenClaw configuration remains native:** use `openclaw onboard`, `openclaw configure`, or the Control UI. The scripts do not try to rewrite provider/model config for you.
- **Back up the whole appliance or just memories:** `rclone` is built in, so you can sync `/data/openclaw` or a narrower directory such as the active `.openclaw` memory data to Dropbox, Google Drive, Box, S3, WebDAV, and many other remotes.
- **Balena operations are still available:** remote logs, terminal access, device variables, public URL, OTA release updates, fleet management, and container restarts all work through the Balena dashboard/CLI.
- **Local and tunnel UI support:** HAProxy handles LAN HTTPS and the Balena public URL, while startup regenerates OpenClaw Control UI origins for the current device, tunnel, LAN IPs, and any custom origin you provide.
- **IPv4-first defaults:** IPv6 is off by default to avoid Raspberry Pi/LAN edge cases with browser origins, self-signed certificates, and mixed tunnel/LAN access. Users who need IPv6 can opt in explicitly.

## Quick Start

Deploy with the button above, or push manually:

```bash
balena push <username>/<fleet-name>
```

On a clean device, first boot does this automatically:

1. Creates `/data/openclaw/versions/<version>/`.
2. Seeds the image-baked OpenClaw binary into that snapshot, or installs `OPENCLAW_VERSION` if you set one.
3. Generates a gateway token unless a real `OPENCLAW_GATEWAY_TOKEN` was provided.
4. Persists that token at `/data/openclaw/gateway.token`.
5. Writes the token and browser origins into the active config.
6. Starts the OpenClaw gateway behind HAProxy.

Find the token in the `openclaw` service logs:

```bash
balena device logs <device-uuid> --service openclaw
```

Look for:

```text
Gateway token source: generated
Gateway token: <first-16-chars>…
```

If you need the full token, open the Balena terminal for the `openclaw` container and run:

```bash
cat /data/openclaw/gateway.token
```

Then open:

- LAN: `https://<device-ip>` and accept the self-signed certificate.
- Balena public URL: `https://<device-uuid>.balena-devices.com/`.

Use the gateway token to log in. Later, if you want Balena to own the token explicitly, set `OPENCLAW_GATEWAY_TOKEN` to that value as a Balena device variable.

On first browser login over the Balena tunnel or LAN, OpenClaw may also require one-time device approval. This is separate from the gateway token. In the Balena terminal:

```bash
openclaw devices list
openclaw devices approve <request-id>
```

If the UI keeps asking, refresh the page and re-run `openclaw devices list`; browser retries can supersede an old request with a new request ID.

## Configure OpenClaw

After the gateway is running, use the Balena terminal or SSH into the `openclaw` container:

```bash
openclaw onboard
openclaw configure
```

The container keeps `/root/.openclaw` pointed at the active version snapshot, so manual commands use the same config and home directory as the running gateway. You can also edit config from the Control UI.

The expected clean-install sequence is:

1. Deploy and wait until the `openclaw` logs show `ready`.
2. Read `/data/openclaw/gateway.token` or set your own token in `OPENCLAW_GATEWAY_TOKEN`.
3. Open the Control UI through the Balena public URL or LAN URL.
4. Enter the gateway token.
5. Approve the browser device once with `openclaw devices approve <request-id>`.
6. Run `openclaw onboard` or use the Control UI config tools to add providers/models.

No script edits provider keys, models, or OpenClaw agent config programmatically.

## Web UI Access

The gateway uses token auth and a regenerated `gateway.controlUi.allowedOrigins` list on every boot. The generated list includes:

- `https://localhost`, `https://127.0.0.1`, and direct gateway loopback origins.
- The container hostname and `.local` hostname where valid.
- Current device IPv4 addresses from `hostname -I`.
- `https://<BALENA_DEVICE_UUID>.balena-devices.com` when Balena exposes the UUID.
- `OPENCLAW_PUBLIC_ORIGIN` when set.
- Any comma-separated values in `OPENCLAW_CONTROL_UI_ORIGINS`.

For the Balena public device URL, you can paste the tunnel URL directly:

```text
OPENCLAW_PUBLIC_ORIGIN=https://<device-uuid>.balena-devices.com/
```

Trailing slashes and paths are normalized away because browsers send origins as `scheme://host[:port]`.

For multiple custom origins such as DNS, Tailscale, or another reverse proxy, set:

```text
OPENCLAW_CONTROL_UI_ORIGINS=https://openclaw.example.com,https://my-pi.ts.net
```

Avoid `allowedOrigins: ["*"]`; OpenClaw treats that as a real browser-origin allow-all policy.

IPv6 is disabled by default. HAProxy binds to `0.0.0.0` only, and startup does not add IPv6 literal addresses to OpenClaw's allowed origins. If you need IPv6:

1. Set `OPENCLAW_ENABLE_IPV6=true`.
2. Add your IPv6 browser origin explicitly, using brackets:

```text
OPENCLAW_CONTROL_UI_ORIGINS=https://[2001:db8::1234]
```

3. Update `proxy/haproxy.cfg` to bind IPv6 as well, for example `bind :::80 v4v6` and `bind :::443 v4v6 ssl crt /etc/haproxy/certs/self-signed.pem`.

If you are not using IPv6 and see Node/OpenClaw outbound connection delays or failures caused by IPv6 DNS results, you can set this Balena device variable:

```text
NODE_OPTIONS=--dns-result-order=ipv4first
```

Balena passes it into the container automatically. It makes Node prefer IPv4 for DNS results used by OpenClaw, but it does not control HAProxy bind addresses or browser allowed origins.

## Upgrades And Rollback

Each OpenClaw version is a self-contained snapshot under `/data/openclaw/versions/<version>/`:

```text
npm-global/       # openclaw binary + node_modules
openclaw.json     # symlink to openclaw-home/.openclaw/openclaw.json
openclaw-home/    # active HOME; contains .openclaw data, config, memories, skills, plugins
```

To upgrade, set `OPENCLAW_VERSION` to a release such as `2026.5.22` and restart the container. The previous snapshot is cloned, the target OpenClaw package is installed into the new snapshot, and the gateway starts from that snapshot.

If installation fails, startup falls back to the previous installed version. On a fresh device with no previous snapshot, it falls back to the image-baked OpenClaw version.

To roll back, set `OPENCLAW_VERSION` to an already installed version and restart. That snapshot is activated as-is, including the OpenClaw binary, config, home data, memories, skills, and plugins from that version.

Old snapshots are pruned by modification time. Set `OPENCLAW_KEEP_VERSIONS` to control how many are kept; default is `3`. Set a larger number if you want a deeper rollback history.

## Device Variables

| Variable | Purpose |
| --- | --- |
| `OPENCLAW_GATEWAY_TOKEN` | Control UI token. Empty, unresolved placeholders, and `changeme` are ignored; startup uses the persisted token file or generates one. |
| `OPENCLAW_PUBLIC_ORIGIN` | Single browser origin for the public UI URL, usually the Balena tunnel URL. |
| `OPENCLAW_CONTROL_UI_ORIGINS` | Extra comma-separated HTTPS/HTTP origins for custom DNS, Tailscale, or another proxy. |
| `OPENCLAW_ENABLE_IPV6` | Set `true` to include IPv6 literal addresses in generated origins. HAProxy still needs IPv6 bind lines if you want direct IPv6 access. Default: `false`. |
| `NODE_OPTIONS` | Optional Node runtime flags. `--dns-result-order=ipv4first` is useful when you want OpenClaw outbound DNS to prefer IPv4. |
| `OPENCLAW_VERSION` | OpenClaw version to activate. Empty uses the image-baked version. |
| `OPENCLAW_KEEP_VERSIONS` | Number of version snapshots to keep. Default: `3`. |
| `OPENCLAW_GATEWAY_STOP` | Set `true` to keep the container alive without starting the gateway. Useful for repair. |
| `HAPROXY_CERT_CN` | Common name for the generated self-signed certificate. Default: `openclaw.local`. |

## Architecture

| Container | Role |
| --- | --- |
| `proxy` | HAProxy TLS termination on ports 80/443. Balena public URL traffic on port 80 is forwarded without redirect because Balena terminates TLS upstream. |
| `openclaw` | OpenClaw gateway on port 8080 with persistent version snapshots under `/data/openclaw`. |

HAProxy forwards `Host`, `X-Forwarded-Proto`, `X-Forwarded-For`, and `X-Real-IP` so OpenClaw sees the browser-facing origin.

## Backups

`rclone` is installed in the `openclaw` container. It supports Dropbox, Google Drive, Box, S3, WebDAV, SFTP, and many other remotes.

```bash
rclone config
rclone sync /data/openclaw remote:backup
```

Back up the whole appliance state:

```bash
rclone sync /data/openclaw remote:openclaw-full
```

Or back up only the active OpenClaw home, which includes config, memories, skills, plugins, and agent data:

```bash
ACTIVE_VERSION="$(cat /data/openclaw/.current-version)"
rclone sync "/data/openclaw/versions/${ACTIVE_VERSION}/openclaw-home/.openclaw" remote:openclaw-home
```

For a memories-only backup, inspect the active `.openclaw` directory after onboarding and sync the specific memory store path OpenClaw created for your setup.

## Local Development

```bash
docker compose up --build
```

Then open `https://localhost` and accept the self-signed certificate.

## License

MIT
