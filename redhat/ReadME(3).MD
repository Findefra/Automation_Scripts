Recommended layout on the host:

__________________________________________

/opt/ops/
├── lib/
│   └── cloud-info.sh
└── bin/
    ├── safe-update.sh
    ├── disk-hygiene.sh
    ├── apply-sysctl.sh
    ├── selinux-app-harden.sh
    ├── firewall-sync.sh
    ├── app-watchdog.sh
    ├── package-drift.sh
    ├── logging-harden.sh
    ├── ssh-harden.sh
    ├── graceful-drain.sh
    └── daily-snapshot.sh
    
---------------------------------------

    /var/log/ops/          # all script logs land here
    /var/lib/ops/          # baselines, snapshots, state files
    /var/run/              # lock files
    
---------------------------------------

	mkdir -p /opt/ops/{lib,bin} /var/log/ops
	chown -R root:root /opt/ops
	chmod 750 /opt/ops/bin/*
	chmod 640 /opt/ops/lib/*
	
---------------------------------------