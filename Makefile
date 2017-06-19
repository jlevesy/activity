DOCKER_REMOTE_ENV=DOCKER_TLS_VERIFY="1" \
		  DOCKER_HOST="tcp://${TARGET_NODE_IP}:2376" \
	   	  DOCKER_CERT_PATH="${HOME}/.docker/machine/machines/${TARGET_NODE}" \
	   	  DOCKER_MACHINE_NAME="${TARGET_NODE}"

all: print_env deliver_admin deliver_monitoring deliver_logs deliver_metrics deliver_app wait show

clean: clean_app clean_logs clean_monitoring clean_metrics clean_admin

show: show_visualizer show_traefik show_grafana

deliver_admin: build_admin push_admin deploy_admin

deliver_monitoring: build_monitoring push_monitoring deploy_monitoring

deliver_logs: build_logs push_logs deploy_logs

deliver_metrics: build_metrics push_metrics deploy_metrics

deliver_app: build_app push_app deploy_app

deploy_admin:
	${DOCKER_REMOTE_ENV} docker stack deploy -c ./stacks/admin/docker-compose.yml admin

deploy_monitoring:
	${DOCKER_REMOTE_ENV} docker stack deploy -c ./stacks/monitoring/docker-compose.yml monitoring

deploy_logs:
	${DOCKER_REMOTE_ENV} docker stack deploy -c ./stacks/logs/docker-compose.yml logs

deploy_metrics:
	${DOCKER_REMOTE_ENV} docker stack deploy -c ./stacks/metrics/docker-compose.yml metrics

deploy_app:
	${DOCKER_REMOTE_ENV} docker stack deploy -c ./stacks/app/docker-compose.yml app

clean_admin:
	${DOCKER_REMOTE_ENV} docker stack rm admin

clean_monitoring:
	${DOCKER_REMOTE_ENV} docker stack rm monitoring

clean_logs:
	${DOCKER_REMOTE_ENV} docker stack rm logs

clean_metrics:
	${DOCKER_REMOTE_ENV} docker stack rm metrics

clean_app:
	${DOCKER_REMOTE_ENV} docker stack rm app

build_admin:
	docker build -t ${REGISTRY}/grafana ./images/grafana

build_monitoring:
	docker build -t ${REGISTRY}/prom_monitoring ./images/prom_monitoring

build_logs:
	docker build -t ${REGISTRY}/logstash ./images/logstash
	docker build -t ${REGISTRY}/elasticsearch ./images/elasticsearch

build_metrics:
	docker build -t ${REGISTRY}/prom_metrics ./images/prom_metrics

build_app:
	docker build -t ${REGISTRY}/dummy ./images/dummy

push_admin:
	docker push ${REGISTRY}/grafana

push_monitoring:
	docker push ${REGISTRY}/prom_monitoring

push_metrics:
	docker push ${REGISTRY}/prom_metrics

push_logs:
	docker push ${REGISTRY}/logstash
	docker push ${REGISTRY}/elasticsearch

push_app:
	docker push ${REGISTRY}/dummy

show_traefik:
	xdg-open http://${DOMAIN}:8080

show_visualizer:
	xdg-open http://visualizer.${DOMAIN}

show_grafana:
	xdg-open http://grafana.${DOMAIN}

wait:
	@echo "Waiting for servers to boot"
	sleep 10

print_env:
	@echo "===== Current environment ====="
	@echo "Registry: ${REGISTRY}"
	@echo "Target Node: ${TARGET_NODE}"
	@echo "Target Node IP: ${TARGET_NODE_IP}"
	@echo "Domain: ${DOMAIN}"
	@echo "==============================="

check_env:
ifndef TARGET_NODE
	$(error REGISTRY is undefined)
endif
ifndef TARGET_NODE_IP
	$(error TARGET_NODE_IP is undefined)
endif
ifndef REGISTRY
	$(error REGISTRY is undefined)
endif
ifndef DOMAIN
	$(error DOMAIN is undefined)
endif

-include check_env

.PHONY: check_env all build push provision_registry deploy_monitoring \
  deploy_monitoring deploy_logs push_monitoring push_logs \
  deploy_admin deploy_monitoring deploy_logs show show_grafana show_traefik \
  show_prometheus show_visualizer
