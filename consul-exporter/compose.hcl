job "consul-exporter" {
  datacenters = ["home"]
  type = "service"

  group "exporter" {

    network {
      mode = "bridge"

      port "metrics" { to = 9107 }
    }

    service {
      name = "consul-exporter"
      port = 9107

      meta {
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
      }
    }

    task "consul-exporter" {
      driver = "docker"

      config {
        image = "prom/consul-exporter:latest"

        args = [
          "--consul.server", "http://consul.service.consul:8500",
          "--log.level", "info",
        ]
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}