# Support

## Getting Help

- **Documentation**: Check the [README.md](README.md) for usage instructions
- **Issues**: Open a [GitHub Issue](https://github.com/itsdarklikehell/fleet-manager/issues) for bug reports or feature requests
- **Discussions**: Use [GitHub Discussions](https://github.com/itsdarklikehell/fleet-manager/discussions) for general questions

## Common Issues

### Telegram not receiving messages

Check that:
1. The bot token is correct
2. The chat IDs are correct
3. The bot has been added to the group

### Cron jobs not running

Check that:
1. The crontab is installed (`crontab -l`)
2. The scripts are executable (`chmod +x scripts/*.sh`)
3. The log file exists (`~/.github_fleet_manager.log`)

### GitHub API rate limits

The GitHub API has rate limits. If you hit them:
1. Wait for the rate limit to reset
2. Use a GitHub token with higher limits
3. Reduce the frequency of API calls
