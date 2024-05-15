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

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    task "backups" {
      driver = "exec"

      config {
        command = "/bin/sh"
        # command line arguments which call Nomad to execute the backup Action
        # add additional backup Actions as desired
        args    = ["-c", <<EOF
echo "backing up Unifi Network MongoDB"
nomad action -job=unifi-network -group=mongodb -task=mongodb backup-mongodb
echo "backing up Bookstack MariaDB"
nomad action -job=bookstack -group=bookstack -task=mariadb backup-mariadb
echo "backing up Immich Postgres DB"
nomad action -job=immich -group=immich-postgres -task=postgres backup-postgres
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
    }
  }
}