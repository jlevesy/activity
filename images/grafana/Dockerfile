FROM grafana/grafana:4.3.2
RUN grafana-cli plugins install grafana-piechart-panel && \
    grafana-cli plugins install grafana-worldmap-panel && \
    grafana-cli plugins install grafana-clock-panel && \
    ls /var/lib/grafana/plugins
