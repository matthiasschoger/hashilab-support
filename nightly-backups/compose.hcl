job "nightly-backups" {
  datacenters = ["home"]
  type        = "batch"

  # runs nightly database backups for all the embedded databases
  # requires that the databases have a backup Action defined which can be called by Nomad

  periodic {
    crons            = ["0 3 * * * *"] # run every day at 3:00
    time_zone        = "Europe/Berlin"
    prohibit_overlap = true
  }

  group "nightly" {

    task "backups" {
      driver = "exec"

      config {
        command = "/bin/sh"
        # command line arguments which call Nomad to execute the backup Action
        # add additional backup Actions as desired
        args    = ["-c", <<EOF
echo "backing up Nomad variables"
nomad operator snapshot save /backup/raft-backup.$(date +"%Y%m%d%H%M").snap
find /backup/* -mtime +3 -exec rm {} \;
echo "backing up Unifi Network MongoDB"
nomad action -job=unifi-network -group=mongodb -task=server backup-mongodb
echo "backing up Bookstack MariaDB"
nomad action -job=bookstack -group=mariadb -task=server backup-mariadb
echo "backing up Immich Postgres DB"
nomad action -job=immich -group=postgres -task=server backup-postgres
echo "finished running nightly backups"
EOF
        ]
      }

      # provide Nomad token with the necessary rights to execute the backup Actions
      template {
        destination = "secrets/variables.env"
        env             = true
        data            = <<EOH
{{- with nomadVar "nomad/jobs/nightly-backups" }}
NOMAD_TOKEN = "{{- .token }}"
TZ = "Europe/Berlin"
{{- end }}
EOH
      }

      resources {
        memory = 100
        cpu    = 100
      }

      volume_mount {
        volume      = "nomad"
        destination = "/backup"
      }    
    }

    volume "nomad" {
      type            = "csi"
      source          = "nomad"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}