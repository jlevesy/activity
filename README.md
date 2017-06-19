# Activity platform

This repository is my solution to an interview test I had to do.

## Problem

Build an infrastructure able to monitor the "activity" of an opensource project.
Which means in other words:
- Being able to monitor data from various sources (APIs...)
- Being able to build graphes on that platform
- Access logs collection Nginx and build dashboards (geoip ?)
- Being able to easilly add and remove source of data

## Scope

- Deploy a POC on a local machine is good enough

## Solution

### Infrastructure

We use containers based infrastructure for various reasons:
  - Lots of already prebuilt images for services I wanted to use
  - No need of complex provisioning of our servers
  - Reduces from start the distance between developement and production: same
    images should run on both environments
  - Facilitates the introduction of redudancy for critical services
  - Makes a little bit more difficult to deal with persistent volumes, but
    there's solutions, for dev and prod
  - Need of the introduction of a container scheduling service

I used docker as a container runtime, as I am already familliar with it, and
and the project benefits from a huge community around it.
As a container scheduling, I chose to experiment with Docker swarm, here are my
motivations:

  - Simple paradigms, compared to k8s. You've got services, stacks, tasks,
    networks and volumes and that's pretty much it.
  - Allow to describe complex application stacks with simple yml files.
  - Integrated solution, you only need to provision a machine with a recent
    version of docker. No dependencies.
  - Deals with a lot of "problems" related to distributed container exectution
    out of the box. For instance service discovery between services, distributed
    networking, load balancing, rolling updates...
  - Seemed to me the most easy to approach according to the time I had, as I was
    only familliar with CoreOS fleet.

Traefik is beeing used as a reverse proxy with that infrastructure,
integrates seemlessly with docker swarm.

At the moment runs on virtualbox, and provisioning is made with a bit of
scripting over docker-machine and systemctl.

On a production system I would definitly have a look about how to provision a
swarm cluster using configuration as code tools just like
[Terraform](https://github.com/hashicorp/terraform) for instance...

### Applicative

#### Metrics collection (metrics stack)

This part is primarily based on [Prometheus](https://github.com/prometheus)

Here are my motivations about that choice.

- Built to collect metrics and stores them efficiently as a time series
- Provides a powerful querying and aggregating language
- Integrates seemlessly with Grafana
- Really active project, huge community and lots of exporters built for the services we
  want to monitor, for instance:
    - https://github.com/infinityworksltd/docker-hub-exporter
    - https://github.com/infinityworksltd/github-exporter
- It's self sufficient, no need of external DBs.
- Easy to configure

And I have also concerns:

- Not built for long term storage...yet ! It is still experimental at the moment.
  However we can tweak retention time and series-file-shrink-ration in order to keep
  the solution reactive. Also I chose to dedicate an instance to metrics collection
  in order to limit numbers of time series. It might need a lot of disk, but should
  do the job.
- It is not possible to add jobs dynamically, we need to edit prometheus
  configuration to add new ones.
- No integration with swarm mode out of the box, it is coming too.
  But there's a DNS discovery services which enables to discovers targets dynamically.
  Which does pretty well the job. Another solution for swarm intergration would have
  been [this](https://github.com/ContainerSolutions/prometheus-swarm-discovery).
- Data storage format will endure breaking change in 2.0
- No snapshot solutions yet, it will come with 2.0, see [here](https://github.com/prometheus/tsdb/pull/88)
  We can default to a cold backup, which implies a downtime, affordable in our
  case.
- No access control

Prometheus has been chosen there for its simplicity. They are other alternatives like
InfluxDB, Beats (alongside an ELK stack) or OpenTSDB. Those solution covers more complex
use cases with a different learning curve, which might not fit in the current need.

#### Log collection (logs stack)

I chose to go for a Logstash + Elasticsearch + Another long term storage backend eventually.

Logstash seemed a good choice for log collection and processing pipeline. My motivations
where:

- Huge community, lots of plugin and support
- Provides Geoip data enrichment out of the box
- Can deal with multiple inputs types, and syslog is out of the box.
- Can write to multiple outputs (ES of course, but others data stores if needed)
- Scalable
- Easy to use.

Elasticsearch seems a good storage / analysis solution in that case too.

- Scales horizontaly, and able to deals with a lot of data
- Not resilient but good enough with a good index rotation setup and backup
  (but it needs some work)
- Powerfull data analysis tool, reachable by a simple API.
- Provides plugins for snapshotting indices and store them on multiple storages
- Can integrate with Grafana too, however this is a bit more complex to use than
  Kibana.

To sum up, logstash seems to be really flexible, and open for platform evolution.
Elasticsearch is a powerful data analysis tool, scalable too. It is however not
resilient, but we can "damage-control" this using for instance a weekly index
rotation and backup on an external storage. If we loose data, we loose it for a week only.
Or we can make logstash write to another storage system, but that would be more
complex.

Primary concern about this solution is that there is no access control and
security for ingested data. As this platform is primarily designed to monitor an
open source project activity, I put security at the bottom of my priority list,
but we should keep that in mind.

It also cost a lot to maintain an Elasticsearch cluster, which is a real
problem. Logstash isn't really lightweight too.

Grafana is being used in order draw graphs and build dashboards as it is easy to
use, and integrates really well with Prometheus and Elasticsearch. I'm not sure we
need kibana for production concerns.

### Other stacks

#### Admin stack

This stacks is in charge of deploying all common resources. It currenlty deploys

- 1 instance Traefik, as a reverse proxy, and primary entrypoint to the platform
- 1 Visualizer, enables to observe tasks allocations in a swarm cluster
- 2 Grafana instances, as it is critical for the platform
- 1 storage backend for grafana, at the moment it is postgresSQL.

It also creates a few networks, needed by others stacks

#### Monitoring stack

I also included a monitoring stack, as it is an important thing in a platform
too. It is based on prometheus too, a difference instance thought because we
don't have the same constraints of retention-time thant the metrics stack.

At the moment it collects data from node status via node-exporter, and also
CGroups data via Cadvisor. At some point I would like to deploy exporters for
Postgres status and Logsatsh, Elasticsearch and Traefik too, as they are critical
components of the platform

On a production instance, I would make prometheus monitoring services redundant.
It should at some point include an Alertmanager.

##### App stack

A dummy nginx webserver, setup to exports its access and errors logs to our
logging stack.

## How to use this

### Requirements (and disclaimer...)

This POC does rely on an NFS share between the host and guest machines.

- docker-machine (>= 0.12.0)
- VBox (>= 5.1.22r115126)
- A decent NFSv4 server

/!\ Disclaimer /!\

I have to say I only tested it on my laptop (Archlinux, kernel: 4.11.3-1-ARCH).
It won't work on non-archlinux systems, `swarm.sh` relies at the moment on
`systemctl` to manage the host NFS server.

### NFS Setup

Add this line to your `/etc/exports`

```
/shared/folder/on/host <vbox_iface_bridge_bcast_addr>/255.255.255.0(rw,async,no_subtree_check,all_squash,anonuid=1000,anongid=50)
```

Pay attention to the `all_squash, anonuid=1000 and anongid=50`

- `all_squash` will remap all uids and gids from the host to the anonymous user
- `anonuid=1000` will force anonymous user UID to 1000 which is docker UID on b2g
- `anongid=50` will force anonymous user GID to 50 which is staff GID on b2g

This way, shared files permissions will be aligned with guests permissions.

### Environment Setup

The given <whatever>.env file defines various arguments used by the stack

  - `REGISTRY` Registry used to provision the platform
  - `DOMAIN` Primary Domain to use for the platform
  - `TARGET_NODE` Node name to interact with
  - `TARGET_NODE_IP` Node IP to interact with
  - `GITHUB_ORGS` Orgs to monitor on github (coma separated list)
  - `DOCKER_HUB_ORGS` Orgs to monitor on the docker hub (coma separated list)

You need to have those enviromments variables defined in order to deploy the
platform

### DNS Setup

This is optional, but you might want to define following DNS rules using your
/etc/hosts or whatever local DNS server you use (works with DNSMasq):

In that example, `DOMAIN` variable is set to `metrics.local`

```
metrics.local <docker-machine ip node-1>
grafana.metrics.local <docker-machine ip node-1>
visualizer.metrics.local <docker-machine ip node-1>
metrics.metrics.local <docker-machine ip node-1>
monitoring.metrics.local <docker-machine ip node-1>
.metrics.local <docker-machine ip node-1>
```

### Starting a swarm cluster

  - `./infra/virtualbox/swarm.sh init`

It will start a 1 manager 3 workers swarm cluster with the following topology

- `node-1` Master, no nfs shares
- `node-2..node-4` Worker , `/data` mounted by nfs on your shared folder

Also the script offers other entrypoints.

  - `./infra/virtualbox/swarm.sh start` Start an already existing cluster
  - `./infra/virtualbox/swarm.sh stop`  Stop an already existing cluster
  - `./infra/virtualbox/swarm.sh clean` Will destroy the cluster and machines
  - `./infra/virtualbox/swarm.sh remount` Will remount nfs shares on worker nodes

### Deploying the solution

  - `source <whatever>.env` if you don't do this, you won't be able to use the
    makefile
  - `make all` will build custom images, publish to given registry and schedule
    all stacks

Other entrypoints are available in the Makefile too.

  - `make deliver_<stack>` Build push and trigger an update for *stack*
  - `make clean_<stack>` removes *stack* from the cluster
  - `make deploy_<stack>` only deploys stack
  - `make push_<stack>` Pushes *stack* images to given registry
  - `make build_<stack>` Builds necessary images for *stack*
  - `make show` open in your browser all interfaces (if you have setup your DNS)

## TODO

### Mandatory

- [x] Introduce a shared data volume on the dev-env
- [x] Introduce Traefik
- [x] Introduce a storage backend for Grafana
- [x] Scale up Grafana
- [x] Add a docker-hub source
- [x] Setup an elasticsearch cluster
- [x] Investigate logstash stack
- [x] Setup a dummy example of log-collected nginx server
- [x] Build dashboards

### Bonus points

- [x] Scale up prometheus (done with monitoring + metrics stacks)
- [x] Add metrics collection for infrastructure, and define alerts
- [ ] Deals with cold backup and restoration on prometheus metrics
- [ ] Scale Elasticsearch (using gossip ?)
- [ ] Automatize indice rotation and backuping in Elasticsearch
- [ ] Introduce an Alert manager
- [ ] Monitor EL stack
- [ ] Monitor Traefik
- [ ] Monitor Postgres
- [ ] Introduce a long term storage for prometheus
- [ ] Backup and restore grafana storage backend ?
- [ ] Variablize and Cross-plaformize `swarm.sh`
