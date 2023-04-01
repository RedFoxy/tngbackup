# tngbackup
The next generation Borg Backup

Da realizzare:
- Sistema di prune automatico
- Sistema di notifica remota in caso di errori
- Sistema di scelta dei singoli run:
--- check
--- list
--- mount
--- extract
--- delete
--- compact
--- info
--- key-change
--- key-export
--- key-import

Suggerimenti:
- Per controllare che il repository esista si piò usare il "borg list" e non il "borg check"

Potenziali bug:
- Create repo remote -> Potebbe non creare il repo e le directory in remoto