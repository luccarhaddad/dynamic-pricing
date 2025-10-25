package com.pricing.api.repository;

import com.pricing.api.entity.FareConfig;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface FareConfigRepository extends JpaRepository<FareConfig, Integer> {
}
