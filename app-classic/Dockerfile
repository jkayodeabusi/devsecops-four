# syntax=docker/dockerfile:1
# =============================================================================
#  Order Tracking API image (DSO-07)
#  Two stages: Maven builds the jar, then only the jar is copied into a
#  distroless runtime (no shell, no package manager, runs as non-root).
#  DSO-01: run scripts/pin-digests.py once to add @sha256 digests to both FROM lines.
# =============================================================================

# ---- Stage 1: build ---------------------------------------------------------
FROM maven:3.9-eclipse-temurin-26@sha256:b2c1ad85954592f9928e84327c65201f308ad9b5d8ed7d5b823717c97bf23fbb AS build
WORKDIR /src
# Copy the pom first: the dependency layer is cached until pom.xml changes.
COPY pom.xml .
RUN mvn -B -q --no-transfer-progress dependency:go-offline
COPY src ./src
# Tests already ran as their own gate (DSO-06); here we only package.
RUN mvn -B -q --no-transfer-progress -DskipTests package

# ---- Stage 2: runtime -------------------------------------------------------
FROM cgr.dev/chainguard/jre:latest@sha256:8bc14490d877809958a50abb74b860c50bfe12939007621f3937158f26843c06
WORKDIR /app
COPY --from=build /src/target/order-tracking.jar /app/order-tracking.jar
# UID 65532 ("nonroot") comes with the base image; never run as root.
USER nonroot
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["java", "-cp", "/app/order-tracking.jar", "com.example.orders.HealthCheck"]
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "/app/order-tracking.jar"]
