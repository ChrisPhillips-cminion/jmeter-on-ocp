FROM registry.access.redhat.com/ubi8/openjdk-11@sha256:ce5c0becf829aca80734b4caf3ab6b76cb00f7d78f4e39fb136636a764dea7f6

USER root

# JMeter version
ENV JMETER_VERSION=5.6.3
ENV JMETER_HOME=/opt/apache-jmeter
ENV PATH=$JMETER_HOME/bin:$PATH

# Install dependencies
RUN microdnf install -y wget tar gzip ca-certificates && \
    microdnf clean all && \
    rm -rf /var/cache/yum

# Download and install JMeter
RUN wget https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz && \
    tar -xzf apache-jmeter-${JMETER_VERSION}.tgz && \
    mv apache-jmeter-${JMETER_VERSION} ${JMETER_HOME} && \
    rm apache-jmeter-${JMETER_VERSION}.tgz

# Download and install JMeter Plugins Manager
RUN wget https://jmeter-plugins.org/get/ -O ${JMETER_HOME}/lib/ext/jmeter-plugins-manager.jar && \
    wget https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar -O ${JMETER_HOME}/lib/cmdrunner-2.3.jar

# Install required plugins using PluginsManagerCMD
# jpgc-casutg provides Concurrency Thread Group for load-test-template.jmx
# jpgc-standard provides Stepping Thread Group for stepping-load-test.jmx
RUN cd ${JMETER_HOME}/lib && \
    java -cp ${JMETER_HOME}/lib/ext/jmeter-plugins-manager.jar org.jmeterplugins.repository.PluginManagerCMDInstaller && \
    ${JMETER_HOME}/bin/PluginsManagerCMD.sh install jpgc-casutg=2.10,jpgc-standard=2.0

# Create results directory and set permissions
RUN mkdir -p /jmeter/results && \
    chown -R 1001:0 /jmeter && \
    chmod -R g=u /jmeter && \
    chown -R 1001:0 ${JMETER_HOME} && \
    chmod -R g=u ${JMETER_HOME}

# Set working directory
WORKDIR /jmeter

# Copy test files
COPY --chown=1001:0 load-test-template.jmx /jmeter/
COPY --chown=1001:0 stepping-load-test.jmx /jmeter/
COPY --chown=1001:0 run-all-tests.sh /jmeter/
COPY --chown=1001:0 run-stepping-test.sh /jmeter/
COPY --chown=1001:0 generate_payload.py /jmeter/

# Make scripts executable
RUN chmod +x /jmeter/run-all-tests.sh /jmeter/run-stepping-test.sh /jmeter/generate_payload.py

# Set default environment variables
ENV HOST=172.30.189.189
ENV PORT=8080
ENV PROTOCOL=http

# Switch to non-root user
USER 1001

# Volume for results
VOLUME ["/jmeter/results"]

# Default command
CMD ["./run-all-tests.sh"]