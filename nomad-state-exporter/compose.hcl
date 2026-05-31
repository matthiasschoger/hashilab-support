job "nomad-state-metrics" {
  datacenters = ["home"]
  type = "service"

  group "exporter" {

    network {
      mode = "bridge"

      port "metrics" { to = 9441 }
      port "telemetry" { to = 9442 }
    }

    service {
      name = "nomad-state-metrics"
      port = 9441

      meta {
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
      }
    }

    service {
      name = "nomad-state-telemetry"
      port = 9442

      check {
        type     = "http"
        path     = "/healthz"
        port     = "telemetry"
        interval = "15s"
        timeout  = "3s"
      }
    }

    task "nomad-state-metrics" {
      driver = "docker"

      config {
        image = "ghcr.io/bhope/nomad-state-metrics:latest"
        ports = ["metrics", "telemetry"]

        args = [
          "-nomad-address", "http://${attr.unique.network.ip-address}:4646",
          "-port", "9441",
          "-telemetry-port", "9442",
          "-poll-interval", "30s",
          "-log-level", "info",
        ]
      }

      # Allow the exporter to reach the local Nomad agent.
      env {
        NOMAD_ADDR = "http://${attr.unique.network.ip-address}:4646"
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}