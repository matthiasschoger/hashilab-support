variable "base_domain" {
  default = "missing.environment.variable"
}

job "diun" {
  datacenters = ["home"]
  type = "service"

  group "diun" {

    ephemeral_disk {
      migrate = true
    }

    task "server" {
      driver = "docker"

      config {
        image = "crazymax/diun:latest"

        args = ["serve", 
                "--config", "/secrets/diun.yaml", 
#                "--log-level", "debug"
        ]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro"    # use TLS certs from host OS, required to talk to Node Red via Traefik (TLS)
        ]      
      }

      env = {
        "TZ" = "Europe/Berlin"

        "DIUN_DB_PATH" = "${NOMAD_ALLOC_DIR}/data/diun.db" # remove as soon as configuration via yaml is possible
      }

      resources {
        memory = 64
        cpu    = 100
      }

      template {
        change_mode   = "restart"
        left_delimiter = "[["
        right_delimiter = "]]"
        destination = "/secrets/diun.yaml"
        data = <<EOH
defaults:
  watchRepo: false
  notifyOn:
    - new
    - update


#db:            # configuration via yaml does not work, using env
#  path: "[[ env "NOMAD_ALLOC_DIR" ]]/data/diun.db"


watch:
  schedule: "0 */6 * * *"
  compareDigest: true
  firstCheckNotif: true
  runOnStartup: true


notif:
  mail:
    host: smtp.lab.${var.base_domain}
[[- with nomadVar "nomad/jobs/diun" ]]
    username: "[[ .email_user ]]"
    password: "[[ .email_pass ]]"
    from: "[[ .email_user ]]"
    to: "[[ .email_receipient ]]"
    insecureSkipVerify: true
[[- end ]]
    templateTitle: 'Diun notification: {{ .Entry.Image }} {{ if (eq .Entry.Status "new") }}is available{{ else }}has been updated{{ end }}'

  webhook:
    endpoint: https://node-red.lab.${var.base_domain}/homelab/diun
    method: POST


providers:
  nomad:
    watchByDefault: true
    address: "http://[[ env "attr.unique.network.ip-address" ]]:4646/"

EOH
      }
    }
  }
}
