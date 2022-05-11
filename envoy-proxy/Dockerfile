FROM envoyproxy/envoy:v1.22.0@sha256:3adaa02a429bb4cf4f65045005e9711bcbf202258f5dae821a646578715ea48f
COPY envoy.yaml /etc/envoy/envoy.yaml
COPY client.example.com.crt /etc/envoy/pki/client.example.com.crt
COPY client.example.com.key /etc/envoy/pki/client.example.com.key
COPY example.com.crt /etc/envoy/pki/example.com.crt
EXPOSE 8080/tcp
RUN chmod go+r /etc/envoy/envoy.yaml
RUN chmod go+r /etc/envoy/pki/example.com.crt
RUN chmod go+r /etc/envoy/pki/client.example.com.crt
RUN chmod go+r /etc/envoy/pki/client.example.com.key