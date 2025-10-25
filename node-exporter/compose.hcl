job "node-exporter" {
  datacenters = ["arbiter", "home", "dmz"]
  type        = "system"

  group "node-exporter" {

    network {
      mode = "bridge"

      port "metrics" { to = 9100 }
    }

    # the service will be picked up by Prometheus from the Consul service directory, using the metrics port in the meta attribute
    service {
      name = "node-exporter"

      port = "metrics"

      meta {
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "prom/node-exporter:latest"

        args  = [
          "--path.rootfs=/hostfs",
          "--path.procfs=/host/proc",
          "--path.sysfs=/host/sys",
          "--path.udev.data=/hostfs/run/udev/data",
          "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|run|hostfs/var/lib/docker|hostfs/var/lib/containerd)($|/)", # ignore docker mounts
          "--collector.mountstats", # required to collect traffic stats for NFS mounts
        ]

        volumes = [
          "/:/hostfs:ro",
          "/proc:/host/proc:ro",
          "/sys:/host/sys:ro"
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      resources {
        memory = 64
        cpu    = 50
      }
    }
  }
}