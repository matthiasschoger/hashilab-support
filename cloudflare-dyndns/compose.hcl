job "cloudflare-dyndns" {
  datacenters = ["home"]
  type        = "service"

  group "cloudflare-dyndns" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    service {
      name = "cloudflare-dyndns"

      port = 80

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
DYNDNS_SERVER_BIND = ":80"
DYNDNS_SERVER_USERNAME = "ddns"
DYNDNS_SERVER_PASSWORD = "ddns"
CLOUDFLARE_API_EMAIL = "{{- .email }}"
CLOUDFLARE_API_TOKEN = "{{- .token }}"
CLOUDFLARE_ZONES_IPV4 = "{{- .zone }}"
CLOUDFLARE_ZONES_IPV6 = "{{- .zone }}"
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