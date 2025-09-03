---
title: Log Explorer (Enterprise)
description: View, search, and export historical logs
sidebar_custom_props:
  myEmoji: 🔭
---

## Introduction

Log Explorer allows you to view, search, and export historical log data from your COSMOS system. You can filter logs by time range, search for specific content, and export the results to CSV or JSON formats for further analysis.

![Log Explorer](/img/log_explorer/log_explorer.png)

## Features

### Log Viewing
- View historical log entries in a scrollable table
- Display log timestamps, log levels (INFO, WARN, ERROR), source of log, user, and messages
- Real-time log updates when viewing recent data (if end time set to a future time)

### Search and Filtering
- Filter logs by date and time range
- Search log content using text-based queries
- Filter by log level (DEBUG, INFO, WARN, ERROR)
- Modify scope to Current Scope for regular log messages or NOSCOPE for system-level logs
- Apply multiple filters simultaneously

### Export Capabilities
- Export filtered log results to CSV format
- Export filtered log results to JSON format
- Download exported files directly from the browser

## Notes

For Enterprise level log searching / filtering, we recommend using an Enterprise-level logging solution like ElasticSearch, Grafana Loki, Splunk, etc. This tool provides a quick and simple interface to view historical logs, but is not suited for searching multi-day amount of logs.