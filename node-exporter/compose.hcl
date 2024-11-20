job "node-exporter" {
  datacenters = ["arbiter", "home", "dmz"]
  type        = "system"

  group "node-exporter" {

    network {
      mode = "bridge"

      port "metrics" { to = 9100 }
    }

    # the service will be picked up by Prometheus from the Consul service directory, including the metrics port in the meta attribute
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
          "--path.rootfs=/host",
          "--collector.mountstats" # required to collect traffic stats for NFS mounts
        ]

        volumes = [
          "/:/host:ro,rslave",
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