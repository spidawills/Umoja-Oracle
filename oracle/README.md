# Umoja Oracle Network

## Overview

Umoja Oracle Network is a decentralized blockchain-based oracle system for verifying price data feeds and rewarding accurate verifiers. The name "Umoja" means "unity" in Swahili, reflecting the collaborative verification approach of this oracle system.

## Features

- **Decentralized Verification**: Multiple verifiers can participate in the network to validate price feeds
- **Incentive Mechanism**: Rewards for accurate verifications to maintain network integrity
- **Embargo Periods**: Time-locked data to prevent front-running and market manipulation
- **Verifier Performance Tracking**: Comprehensive statistics on verifier activities
- **Verification Records**: Immutable history of all verifications for transparency

## Technical Architecture

Umoja Oracle Network is built on Stacks blockchain using Clarity smart contracts, providing a secure and transparent verification system.

### Core Components

1. **Network Controller**: Manages the overall network state and feed registration
2. **Price Feeds**: Structured data sources with verification requirements
3. **Verifier System**: Tracks participation and performance of data verifiers
4. **Verification Records**: Immutable history of all verification activities

### Smart Contract Structure

```clarity
;; Main data structures
(define-map price-feeds
    uint
    {
        data-source: (string-utf8 256),
        verification-signature: (buff 32),
        embargo-end: uint,
        incentive: uint,
        verified: bool
    }
)

(define-map verifier-stats
    principal
    {
        active-feed: uint,
        verified-feeds: (list 20 uint),
        last-verification: uint,
        total-verifications: uint
    }
)
