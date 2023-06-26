# Security - Best Practices

- As a start read our [Backup-Recovery-Best-Practices](https://github.com/Fonta1n3/FullyNoded/blob/master/Docs/Backup-Recovery-Best-Practices.md)

Fully Noded uses defensive code to protect your data from attackers.

### Unlock password

It is recommended to always utilize the unlock password as simple pins and biometrics can be all too
easily used or brute forced.

To add a password: `Settings` > `Security` > `App unlock password`

It is recommended to use a 6 random words (half of a dummy signer) that you have saved offline somewhere.

The app password persists between app deletions. As does the timeout period between allowed attempts
at inputting the password. Fully Noded uses your keychain in a clever way to ensure your unlock password is impossible to brute force.

If you forget the unlock password you can tap the `reset app` button which will prompt your for 2fa
and only upon successful 2fa will allow you to delete the local data for the app and wipe the keychain.
This means your encrypted iCloud backup will still be intact and accessible if you have the original
encryption key for the backup.

***It is strongly recommended to use this password, it can prevent most any attacker from gaining access***

### Biometrics

It is recommended to keep biometrics *disabled* if you are concerned about any attacker
easily gaining access to your device and potentially your btc. It is far to easy
for an attacker to immobilize you and simply point your phone at your face to unlock it.

