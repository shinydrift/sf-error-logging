FROM arc-sandbox:latest
# Add project-specific dependencies below

# Install Node.js LTS and Salesforce CLI
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global @salesforce/cli \
    && sf --version
