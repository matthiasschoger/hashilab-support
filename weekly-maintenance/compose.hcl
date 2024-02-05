job "weekly-maintenance" {
  datacenters = ["home"]
  type        = "sysbatch"

  # runs weekly maintenance jobs on all nodes, i.e. prune dangling docker containers which are no longer in use
  
  periodic {
    crons            = ["15 3 * * Sun"] # run every Sunday at 3:15
    time_zone        = "Europe/Berlin"
    prohibit_overlap = true
  }

  group "docker" {

    task "maintenance" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        # add additional weekly maintenance actions as desired
        args    = ["-c", <<EOF
echo "cleaning up docker resources"
docker system prune --all --force
echo "finished cleaning up docker resources"
EOF
        ]
      }

      resources {
        memory = 100
        cpu    = 100
      }
    }
  }
}