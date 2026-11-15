package com.circleguard.auth.client;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;
import java.util.*;

@Component
public class IdentityClient {
    // In a real microservice, this would use Feign or WebClient
    private final RestTemplate restTemplate;
    private static final String IDENTITY_URL = "http://localhost:8083/api/v1/identities/map";

    // Constructor que usa Spring (el otro existe solo para inyectar un RestTemplate en pruebas)
    @Autowired
    public IdentityClient() {
        this(new RestTemplate());
    }

    // Permite inyectar un RestTemplate controlado en las pruebas
    IdentityClient(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    public UUID getAnonymousId(String realIdentity) {
        Map<String, String> request = Map.of("realIdentity", realIdentity);
        Map<?, ?> response = restTemplate.postForObject(IDENTITY_URL, request, Map.class);
        if (response == null || response.get("anonymousId") == null) {
            throw new IllegalStateException("Identity service returned no anonymousId");
        }
        return UUID.fromString(response.get("anonymousId").toString());
    }
}
