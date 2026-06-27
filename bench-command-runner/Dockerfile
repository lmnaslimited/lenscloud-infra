ARG BENCH_BASE_IMAGE=ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.1
FROM ${BENCH_BASE_IMAGE}

USER root
COPY runner.py /usr/local/bin/lenscloud-bench-command-runner
RUN chmod 0755 /usr/local/bin/lenscloud-bench-command-runner

USER frappe
WORKDIR /home/frappe/frappe-bench
ENTRYPOINT ["/usr/local/bin/lenscloud-bench-command-runner"]
