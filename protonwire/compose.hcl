job "protonwire" {
  datacenters = ["home"]
  type        = "service"

  group "vpn" {

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    # service {
    #   name = "protonmail-smtp"

    #   port = 1025

    #  meta {
    #     envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
    #   }
    #   connect {
    #     sidecar_service {
    #       proxy {
    #         config {
    #           envoy_prometheus_bind_addr = "0.0.0.0:9102"
    #         }
    #       }
    #     }

    #     sidecar_task {
    #       resources {
    #         cpu    = 50
    #         memory = 64
    #       }
    #     }
    #   }    
    # }

    task "server" {
      driver = "docker"

      config {
        image = "ghcr.io/tprasadtp/protonwire:latest"

        cap_add = ["NET_ADMIN"]
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
#        destination = "${NOMAD_SECRETS_DIR}/vars.env"
        destination = "local/vars.env"
        env             = true
        data            = <<EOH
{{- with nomadVar "nomad/jobs/protonwire" }}
PROTONVPN_SERVER      = "{{ .endpoint }}"
#WIREGUARD_PRIVATE_KEY = "/secrets/private-key"
WIREGUARD_PRIVATE_KEY = "/local/private-key"
KILL_SWITCH           = "0"

DEBUG                 = "1" # set to "1" for debug output
{{- end }}
EOH
      }

      template {
#        destination = "${NOMAD_SECRETS_DIR}/private-key"
        destination = "local/private-key"
        perms = "400"
        data = <<EOH
{{- with nomadVar "nomad/jobs/protonwire" }}{{- .private_key }}{{- end }}
EOH
      }

      resources {
        memory = 128
        cpu    = 200
      }
    }
  }
}