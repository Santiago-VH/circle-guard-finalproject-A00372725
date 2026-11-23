package com.circleguard.auth.client;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;
import java.util.*;

@Component
public class IdentityClient {
    // In a real microservice, this would use Feign or WebClient
    private final RestTemplate restTemplate;
    private final String identityUrl;

    // Constructor que usa Spring. La URL del identity-service es configurable
    // (identity.base-url) para que funcione también dentro de contenedores.
    @Autowired
    public IdentityClient(@Value("${identity.base-url:http://localhost:8083}") String identityBaseUrl) {
        this(new RestTemplate(), identityBaseUrl);
    }

    // Permite inyectar un RestTemplate controlado en las pruebas
    IdentityClient(RestTemplate restTemplate, String identityBaseUrl) {
        this.restTemplate = restTemplate;
        this.identityUrl = identityBaseUrl + "/api/v1/identities/map";
    }

    public UUID getAnonymousId(String realIdentity) {
        Map<String, String> request = Map.of("realIdentity", realIdentity);
        Map<?, ?> response = restTemplate.postForObject(identityUrl, request, Map.class);
        if (response == null || response.get("anonymousId") == null) {
            throw new IllegalStateException("Identity service returned no anonymousId");
        }
        return UUID.fromString(response.get("anonymousId").toString());
    }
}
