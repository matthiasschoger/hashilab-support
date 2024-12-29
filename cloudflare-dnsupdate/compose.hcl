job "cloudflare-dyndns" {
  datacenters = ["home"]
  type        = "service"

  group "cloudflare-dnsupdate" {

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    service {
      name = "cloudflare-dnsupdate"

      port = 8080

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }
    }

    service {
      name = "cloudflare-dnsupdate-metrics"

      port = 9090

      check {
        type     = "http"
        path     = "/healthz"
        interval = "5s"
        timeout  = "2s"
        expose   = true # required for Connect
      }

      connect {
        sidecar_service {
          proxy { }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }
    }

    task "server" {

      driver = "docker"

      config {
        # receives a callback from the router when the IP changes -> update Cloudflare DNS entries

        image = "ghcr.io/cromefire/fritzbox-cloudflare-dyndns:latest"

        # example URL: 192.168.0.3:1080/ip?v4=<ipaddr>&v6=<ip6addr>&prefix=<ip6lanprefix>&username=<username>&password=<pass>
        # adjust to your router as needed
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        destination = "secrets/variables.env"
        env = true
        data = <<EOH
{{- with nomadVar "nomad/jobs/cloudflare-dyndns" }}
# metrics and health check port
METRICS_BIND = ":9090"

CLOUDFLARE_API_EMAIL = "{{- .email }}"
CLOUDFLARE_API_TOKEN = "{{- .token }}"
CLOUDFLARE_ZONES_IPV4 = "{{- .zone }}"
CLOUDFLARE_ZONES_IPV6 = "{{- .zone }}"
# DEVICE_LOCAL_ADDRESS_IPV6 = "::1:0:0:0:2" # UXG-lite postfix
{{- end }}
EOH
      }

      resources {
        memory = 50
        cpu    = 50
      }
    }
  }
}