// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library PythLazerStructs {
    enum Channel {
        Invalid,
        RealTime,
        FixedRate50,
        FixedRate200,
        FixedRate1000
    }

    enum PriceFeedProperty {
        Price,
        BestBidPrice,
        BestAskPrice,
        PublisherCount,
        Exponent,
        Confidence,
        FundingRate,
        FundingTimestamp,
        FundingRateInterval,
        MarketSession,
        EmaPrice,
        EmaConfidence,
        FeedUpdateTimestamp
    }

    enum PropertyState {
        NotApplicable,
        ApplicableButMissing,
        Present
    }

    enum MarketSession {
        Regular,
        PreMarket,
        PostMarket,
        OverNight,
        Closed
    }

    struct Feed {
        uint256 triStateMap;
        uint32 feedId;
        int64 _price;
        uint16 _publisherCount;
        int16 _exponent;
        int64 _bestBidPrice;
        int64 _bestAskPrice;
        uint64 _confidence;
        int64 _fundingRate;
        uint64 _fundingTimestamp;
        uint64 _fundingRateInterval;
        MarketSession _marketSession;
        int64 _emaPrice;
        uint64 _emaConfidence;
        uint64 _feedUpdateTimestamp;
    }

    struct Update {
        uint64 timestamp;
        Channel channel;
        Feed[] feeds;
    }
}
