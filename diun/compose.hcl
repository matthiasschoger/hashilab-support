job "diun" {
  datacenters = ["home"]
  type = "service"

  group "diun" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    ephemeral_disk {
      migrate = true
    }

    task "server" {
      driver = "docker"

      config {
        image = "crazymax/diun:latest"

        args = ["serve", 
                "--config", "/local/diun.yaml", 
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
        cpu    = 50
      }

      template {
        change_mode   = "restart"
        destination = "/local/diun.yaml"
        data = <<EOH
defaults:
  watchRepo: false
  notifyOn:
    - new
    - update


#db:            # configuration via yaml does not work, using env
#  path: "{{ env "NOMAD_ALLOC_DIR" }}/data/diun.db"


watch:
  schedule: "0 */6 * * *"
  compareDigest: true
  firstCheckNotif: true
  runOnStartup: true


notif:
  teams:
{{- with nomadVar "nomad/jobs/diun" }}
    webhookURL: {{ .webhook_url }}
{{- end }}

  webhook:
    endpoint: https://node-red.lab.home/homelab/diun
    method: POST

#  mail:
#    host: smtp.lab.home
#{{- with nomadVar "nomad/jobs/diun" }}
#    username: {{ .email_user }}
#    password: {{ .email_pass }}
#{{- end }}
#    from: "matthias@schoger.net"
#    to: "matthias@schoger.net"


providers:
  nomad:
    watchByDefault: true
    address: "http://{{ env "attr.unique.network.ip-address" }}:4646/"

EOH
      }
    }
  }
}



/*
{"diun_version":"v4.24.0","hostname":"56d36f54b404","status":"new","provider":"nomad","image":"docker.io/crazymax/diun:4.24.0","hub_link":"https://github.com/crazy-max/diun","mime_type":"application/vnd.docker.distribution.manifest.list.v2+json","digest":"sha256:fa80af32a7c61128ffda667344547805b3c5e7721ecbbafd70e35bb7bb7c989f","created":"2022-12-29T11:25:32.442841563Z","platform":"linux/amd64","metadata":{"job_id":"diun","job_name":"diun","job_namespace":"default","job_status":"running","task_driver":"docker","task_name":"server","task_user":"","taskgroup_name":"diun"}}


curl -X POST  -H "Authorization: Bearer ${NOMAD_TOKEN}" -d '{"AllTasks": true }' \
    http://master.home:4646/v1/client/allocation/2658ce9d-0d14-f8bd-42f5-b0e00cc18fe5/restart

curl -X POST  -H "Authorization: Bearer ${NOMAD_TOKEN}" -d '{"filter": "name=nginx" }' \
    http://master.home:4646/v1/jobs

curl --get -H "Authorization: Bearer ${NOMAD_TOKEN}"  \
    http://master.home:4646/v1/allocations --data-urlencode 'filter=JobID contains "diun"' | jq


"ClientStatus": "running",

*/