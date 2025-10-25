package com.pricing.api.repository;

import com.pricing.api.entity.ZonePriceSnapshot;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface ZonePriceSnapshotRepository extends JpaRepository<ZonePriceSnapshot, Integer> {
}
