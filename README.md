

## Cloudflered
Don't forget to add service to crontab for restart run `crontab -e` and add
`@reboot cloudflared tunnel --config ~/service/cloudflared/config.yml run pc-dev`
