package com.circleguard.promotion.service;

import com.circleguard.promotion.model.graph.CircleNode;
import com.circleguard.promotion.repository.graph.CircleNodeRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CircleServiceTest {

    @Mock
    private CircleNodeRepository circleRepository;

    @Mock
    private HealthStatusService healthStatusService;

    @InjectMocks
    private CircleService circleService;

    @Test
    void createCircle_GeneratesMeshInviteCode() {
        when(circleRepository.existsByInviteCode(anyString())).thenReturn(false);
        when(circleRepository.save(any(CircleNode.class))).thenAnswer(inv -> inv.getArgument(0));

        CircleNode circle = circleService.createCircle("Ingesoft V", "building-1");

        assertEquals("Ingesoft V", circle.getName());
        assertTrue(circle.getInviteCode().matches("MESH-[A-HJ-NP-Z2-9]{4}"),
                "Código inesperado: " + circle.getInviteCode());
    }

    @Test
    void createCircle_RetriesWhenInviteCodeAlreadyExists() {
        when(circleRepository.existsByInviteCode(anyString())).thenReturn(true, false);
        when(circleRepository.save(any(CircleNode.class))).thenAnswer(inv -> inv.getArgument(0));

        circleService.createCircle("Ingesoft V", "building-1");

        verify(circleRepository, times(2)).existsByInviteCode(anyString());
    }
}
