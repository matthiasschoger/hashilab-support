<h1>Hashilab Support</h1>

<h2>Motivation</h2>

This project was born out of boredom during the Covid epedemic, when I wanted to replace my already existing Docker homelab with something more advanced. After playing around with k8s for a bit, I decided that Nomad is a great fit for a hobby project, compared to k8s which felt more like something you would do for a job.

With k8s, it felt to me like I was reciting the rotes of the church of Helm, without really understanding what I was doing or why. With Nomad and Consul, I could "grok" the concepts without making it a job and find solutions to the specific issues I was facing.

<h2>Goals of this project</h2>

My main goals for my new homelab were the following
- Resiliency - which means high-availablity to me. I want to shut down or lose any node, and my cluster should heal itself, with all services being available again.
- I'm a sucker for graph p*rn, and want to have as much insight as possible into what my homelab is currently doing.
- Scratch my technical itch. Since I move into a sales position right before Covid, I needed some tech stuff to do.

To keep the jobs manageable, I've split them into three repositories
- [hashilab-core](https://github.com/matthiasschoger/hashilab-core): Basic infrastructure which contains load-balancing, reverse proxy, DNS and ingress management
- [hashilab-support](https://github.com/matthiasschoger/hashilab-support): Additional operational stuff like metrics management and visualization, maintenance tasks and much more stuff to run the cluster more effienctly
- [hashilab-apps](https://github.com/matthiasschoger/hashilab-apps): End-user apps like Vaultwarden or Immich


<h2>Hashilab-support</h2>

The "support" repository defines mostly operational stuff which makes it easier to manage the cluster and give insight into the inner workings of the whole setup. In addition, it exposes some services on the internet via Cloudflare Tunnel.

- cloudflared - Cloudflare tunnel which exposes some services on the internet. 
- diun - Update notifications when new releases are available for my services.
- log-collection - Log file aggregation of all servers into Loki.
- loki - Central log file aggregation.
- nightly-backups - Cron jobs which do online backups of the databases via Nomad Actions.
- node-exporter - Provides metrics of all the VMs to Prometheus.
- portainer - Container management, no longer in use.
- prometheus - Metrics database, which picks up metrics from the nodes, services and Consul Connect and stores them in a time-series database. Used by Grafana to do the graph p*rn thing ...
- proton-bridge - Bridge to my email service Proton Mail. Provides an interface for my services to send out email notifications.
- weekly-maintenance - Weekly job which runs clean up jobs on all my nodes.
