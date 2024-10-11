# Use a minimal base image
FROM golang:1.20-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git

# Set the working directory
WORKDIR /app

# Copy the Go module files
COPY go.mod ./

# Download the Go module dependencies
RUN go mod download && go mod verify

# Copy the source code
COPY . ./

# Build the Go binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app .

# Use a minimal base image for runtime
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache ca-certificates graphviz

# Install Terraform
RUN wget https://releases.hashicorp.com/terraform/1.9.7/terraform_1.9.7_linux_amd64.zip \
    && unzip terraform_1.9.7_linux_amd64.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform_1.9.7_linux_amd64.zip

# Set the working directory
WORKDIR /app

# Copy the built binary from the builder stage
COPY --from=builder /app/app ./

# Copy the patternsFile.txt to the app directory
COPY patternsFile.txt /app/patternsFile.txt

# Set the executable permissions for the binary
RUN chmod +x ./app

# Expose the port that the web service listens on
EXPOSE 80

# Set the entrypoint command
CMD ["./app"]

# Allow setting BaseURL via environment variable (optional override)
ENV BASE_URL=""

# Allow setting HMAC_KEY via environment variable
ENV HMAC_KEY=""