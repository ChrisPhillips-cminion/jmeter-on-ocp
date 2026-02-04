FROM registry.access.redhat.com/ubi8/openjdk-11@sha256:ce5c0becf829aca80734b4caf3ab6b76cb00f7d78f4e39fb136636a764dea7f6

# JMeter version
ENV JMETER_VERSION=5.6.3
ENV JMETER_HOME=/opt/apache-jmeter
ENV PATH=$JMETER_HOME/bin:$PATH

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download and install JMeter
RUN wget https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz && \
    tar -xzf apache-jmeter-${JMETER_VERSION}.tgz && \
    mv apache-jmeter-${JMETER_VERSION} ${JMETER_HOME} && \
    rm apache-jmeter-${JMETER_VERSION}.tgz

# Create results directory
RUN mkdir -p /jmeter/results

# Set working directory
WORKDIR /jmeter

# Copy test files
COPY load-test-template.jmx /jmeter/
COPY run-all-tests.sh /jmeter/
COPY generate_payload.py /jmeter/

# Make scripts executable
RUN chmod +x /jmeter/run-all-tests.sh /jmeter/generate_payload.py

# Set default environment variables
ENV HOST=172.30.189.189
ENV PORT=8080
ENV PROTOCOL=http

# Volume for results
VOLUME ["/jmeter/results"]

# Default command
CMD ["./run-all-tests.sh"]
