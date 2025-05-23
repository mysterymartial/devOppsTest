FROM maven:3-eclipse-temurin-21 AS build
WORKDIR /app
COPY . .
RUN mvn clean package -DskipTests=true

FROM eclipse-temurin:21-jre
COPY --from=build /app/target/lucky-1.0-SNAPSHOT.jar lucky.jar
ENTRYPOINT ["java", "-Dspring.profiles.active=prod", "-jar", "lucky.jar"]
EXPOSE 8080git