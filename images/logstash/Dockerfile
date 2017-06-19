FROM logstash:5-alpine
ADD ./pipeline /usr/share/logstash/pipeline
ADD ./template /usr/share/logstash/template

EXPOSE 6002

CMD ["-f", "/usr/share/logstash/pipeline/syslog.conf"]
