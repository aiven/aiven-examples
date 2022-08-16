package com.example;

import org.apache.flink.api.common.functions.MapFunction;

public class StringCapitalizer implements MapFunction<String, String> {
    public String map(String s) {
        return s.toUpperCase();
    }
}