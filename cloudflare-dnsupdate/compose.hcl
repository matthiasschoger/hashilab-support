job "cloudflare-dyndns" {
  datacenters = ["home"]
  type        = "service"

  group "cloudflare-dnsupdate" {

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    # receives a callback from the router when the IP changes -> update Cloudflare DNS entries
    #  example URL: 192.168.0.3:1080/ip?v4=<ipaddr>&v6=<ip6addr>&prefix=<ip6lanprefix>&username=<username>&password=<pass>
    #  adjust to your router as needed
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
            cpu    = 10
            memory = 32
          }
        }
      }
    }

    task "server" {
     driver = "docker"

      config {
        image = "ghcr.io/cromefire/fritzbox-cloudflare-dyndns:latest"
      }

      env {
        TZ = "Europe/Berlin"

        # Fritz!Box endpoint for polling
        FRITZBOX_ENDPOINT_URL = "http://fritz.box:49000"
        FRITZBOX_ENDPOINT_INTERVAL = "300s"
        FRITZBOX_ENDPOINT_TIMEOUT  = "10s"
      }

      template {
        destination = "secrets/variables.env"
        env = true
        data = <<EOH
{{- with nomadVar "nomad/jobs/cloudflare-dyndns" }}
CLOUDFLARE_API_EMAIL  = "{{- .email }}"
CLOUDFLARE_API_TOKEN  = "{{- .token }}"
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