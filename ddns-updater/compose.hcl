job "ddns-updater" {
  datacenters = ["home"]
  type        = "service"

  group "ddns-updater" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    ephemeral_disk {
      migrate = true
    }

    service {
        name = "ddns-updater"

        port = 8000
        
        check {
        type     = "http"
        path     = "/"
        interval = "5s"
        timeout  = "2s"
        expose   = true # required for Connect
        }

        tags = [
          "traefik.enable=true",
          "traefik.consulcatalog.connect=true",
          "traefik.http.routers.ddns.rule=Host(`ddns.lab.home`)",
          "traefik.http.routers.ddns.entrypoints=websecure"
        ]

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
        image = "qmcgaw/ddns-updater:latest"
      }

      env {
        TZ = "Europe/Berlin"
        IPV6_PREFIX = "/56"
        DATADIR = "${NOMAD_ALLOC_DIR}/data"
      }

      template {
        destination = "${NOMAD_ALLOC_DIR}/data/config.json"
        data = <<EOH
{{- with nomadVar "nomad/jobs/ddns-updater" }}
{
    "settings": [
        {
            "provider": "cloudflare",
            "zone_identifier": "{{- .zone_id }}",
            "domain": "schoger.net",
            "host": "wg",
            "ttl": 600,
            "token": "{{- .token }}",
            "ip_version": "ipv4"
        }
    ]
}
{{- end }}
EOH
      }

      resources {
        memory = 50
        cpu    = 100
      }
    }
  }
}