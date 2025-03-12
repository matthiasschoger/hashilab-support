variable "base_domain" {
  default = "missing.environment.variable"
}

job "traefik-dmz" {
  datacenters = ["dmz"]
  type        = "service"

  # Traefik instance for the DMZ, routes traffic from cloudflared to the desired services
  group "traefik-dmz" {

    network {
      mode = "bridge"

      port "metrics" { to = 1080 } # Traefik metrics via API port
      port "crowdsec_metrics" { to = 6060 } # Crowdsec metrics 

      port "envoy_metrics_api" { to = 9102 }
      port "envoy_metrics_dmz_http" { to = 9103 }
    }

    ephemeral_disk {
      # Used to cache Crowdsec transient data, Nomad will try to preserve the disk between job updates.
      size    = 300 # MB
      migrate = true
    }

    service {
      name = "traefik-dmz-api"

      port = 1080

      check {
        type     = "http"
        path     = "/ping"
        interval = "5s"
        timeout  = "2s"
        expose   = true # required for Connect
      }

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_api}" # make envoy metrics port available in Consul
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
        crowdsec_metrics_port = "${NOMAD_HOST_PORT_crowdsec_metrics}"
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

      tags = [ # registers the DMZ Traefik instance with the home instance
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.traefik-dmz.rule=Host(`dmz.lab.${var.base_domain}`)",
        "traefik.http.routers.traefik-dmz.entrypoints=websecure"
      ]
    }

    # Cloudflare entrypoint, is bound to localhost:80 in the cloudflared job via Consul Connect
    service {
      name = "traefik-dmz-http"

      port = 80

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_dmz_http}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9103"
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
        image = "traefik:latest"

        args = [ "--configFile=/local/traefik.yaml" ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/certs/origin/${var.base_domain}.crt"
        perms = "600"
        data = <<EOH
{{- with nomadVar "nomad/jobs/traefik-dmz" }}{{- .origin_certificate }}{{- end }}
EOH
      }
      template {
        destination = "${NOMAD_SECRETS_DIR}/certs/origin/${var.base_domain}.key"
        perms = "600"
        data = <<EOH
{{- with nomadVar "nomad/jobs/traefik-dmz" }}{{- .origin_private_key }}{{- end }}
EOH
      }

      template {
        destination = "local/traefik.yaml"
        data        = file("traefik.yaml")
      }

      dynamic "template" {
        for_each = fileset(".", "conf/*")

        content {
          data            = file(template.value)
          destination     = "local/${template.value}"
        }
      }

      resources {
        memory = 384
        cpu    = 400
      }
    }
  

    # see https://blog.lrvt.de/configuring-crowdsec-with-traefik/
    task "crowdsec" {

      driver = "docker"

      config {
        image = "crowdsecurity/crowdsec:latest"

        mounts = [ # map config files into container
          {
            type   = "bind"
            source = "local/crowdsec/config.yaml.local"
            target = "/etc/crowdsec/config.yaml.local"
          },
          {
            type   = "bind"
            source = "local/crowdsec/acquis.yaml"
            target = "/etc/crowdsec/acquis.yaml"
          }
        ]
      }

      env {
        TZ = "Europe/Berlin"

        COLLECTIONS = "crowdsecurity/traefik crowdsecurity/http-cve crowdsecurity/appsec-generic-rules crowdsecurity/appsec-virtual-patching crowdsecurity/linux crowdsecurity/base-http-scenarios crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules"
      }

      template {
        destination = "/local/crowdsec/config.yaml.local"
        data = <<EOH
common:
#  log_level: debug
  log_level: info

config_paths:
#  config_dir: "<path_to_crowdsec_config_folder>"
  data_dir: "/alloc/data/crowdsec/data"

#db_config:
#  db_path:  "/alloc/data/crowdsec/db/crowdsec.db"

prometheus:
  enabled: true
  level: full
  listen_addr: 0.0.0.0

EOH
      }


      template {
        destination = "/local/crowdsec/acquis.yaml"
        data = <<EOH
# appsec
listen_addr: 127.0.0.1:7422
appsec_config: crowdsecurity/appsec-default
name: AppSecComponent
source: appsec
labels:
  type: appsec

---

# Traefik
poll_without_inotify: false
filenames:
  - {{ env "NOMAD_ALLOC_DIR" }}/traefik/*.log # Traefik access log location
labels:
  type: traefik

EOH
      }

      resources {
        memory = 256
        cpu    = 400
      }

      volume_mount {
        volume      = "crowdsec-db"
        destination = "/var/lib/crowdsec/data"
      }    

      volume_mount {
        volume      = "crowdsec-etc"
        destination = "/etc/crowdsec"
      }    
    }
  
    volume "crowdsec-db" {
      type            = "csi"
      source          = "crowdsec-db"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  
    volume "crowdsec-etc" {
      type            = "csi"
      source          = "crowdsec-etc"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}