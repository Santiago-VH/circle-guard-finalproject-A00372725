package com.circleguard.auth.client;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.http.HttpMethod.POST;

class IdentityClientTest {

    private static final String URL = "http://localhost:8083/api/v1/identities/map";

    private MockRestServiceServer server;
    private IdentityClient client;

    @BeforeEach
    void setUp() {
        RestTemplate restTemplate = new RestTemplate();
        server = MockRestServiceServer.bindTo(restTemplate).build();
        client = new IdentityClient(restTemplate, "http://localhost:8083");
    }

    @Test
    void getAnonymousId_ReturnsIdFromIdentityService() {
        UUID expected = UUID.randomUUID();
        server.expect(requestTo(URL)).andExpect(method(POST))
                .andRespond(withSuccess("{\"anonymousId\":\"" + expected + "\"}", MediaType.APPLICATION_JSON));

        assertEquals(expected, client.getAnonymousId("student@icesi.edu.co"));
        server.verify();
    }

    @Test
    void getAnonymousId_WhenResponseHasNoId_ThrowsIllegalState() {
        server.expect(requestTo(URL)).andExpect(method(POST))
                .andRespond(withSuccess("{}", MediaType.APPLICATION_JSON));

        assertThrows(IllegalStateException.class, () -> client.getAnonymousId("student@icesi.edu.co"));
    }

    @Test
    void getAnonymousId_WhenResponseIsEmpty_ThrowsIllegalState() {
        server.expect(requestTo(URL)).andExpect(method(POST))
                .andRespond(withSuccess());

        assertThrows(IllegalStateException.class, () -> client.getAnonymousId("student@icesi.edu.co"));
    }
}
