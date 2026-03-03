// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PythLazerStructs} from "./PythLazerStructs.sol";

library PythLazerLib {
    function _setTriState(
        PythLazerStructs.Feed memory feed,
        uint8 propId,
        PythLazerStructs.PropertyState state
    ) private pure {
        uint256 mask = ~(uint256(3) << (2 * propId));
        feed.triStateMap =
            (feed.triStateMap & mask) |
            (uint256(uint8(state)) << (2 * propId));
    }

    function _setApplicableButMissing(
        PythLazerStructs.Feed memory feed,
        uint8 propId
    ) private pure {
        _setTriState(feed, propId, PythLazerStructs.PropertyState.ApplicableButMissing);
    }

    function _setPresent(
        PythLazerStructs.Feed memory feed,
        uint8 propId
    ) private pure {
        _setTriState(feed, propId, PythLazerStructs.PropertyState.Present);
    }

    function _hasValue(
        PythLazerStructs.Feed memory feed,
        uint8 propId
    ) private pure returns (bool) {
        return ((feed.triStateMap >> (2 * propId)) & 3) ==
            uint256(uint8(PythLazerStructs.PropertyState.Present));
    }

    function _isRequested(
        PythLazerStructs.Feed memory feed,
        uint8 propId
    ) private pure returns (bool) {
        return ((feed.triStateMap >> (2 * propId)) & 3) != 0;
    }

    function _readBytes1(
        bytes memory data,
        uint16 pos
    ) private pure returns (uint8 value) {
        assembly {
            let word := mload(add(add(data, 0x20), pos))
            value := shr(248, word)
        }
    }

    function _readBytes2(
        bytes memory data,
        uint16 pos
    ) private pure returns (uint16 value) {
        assembly {
            let word := mload(add(add(data, 0x20), pos))
            value := shr(240, word)
        }
    }

    function _readBytes4(
        bytes memory data,
        uint16 pos
    ) private pure returns (uint32 value) {
        assembly {
            let word := mload(add(add(data, 0x20), pos))
            value := shr(224, word)
        }
    }

    function _readBytes8(
        bytes memory data,
        uint16 pos
    ) private pure returns (uint64 value) {
        assembly {
            let word := mload(add(add(data, 0x20), pos))
            value := shr(192, word)
        }
    }

    function parsePayloadHeader(
        bytes memory update
    )
        public
        pure
        returns (
            uint64 timestamp,
            PythLazerStructs.Channel channel,
            uint8 feedsLen,
            uint16 pos
        )
    {
        uint32 FORMAT_MAGIC = 2479346549;

        pos = 0;
        uint32 magic = _readBytes4(update, pos);
        pos += 4;
        if (magic != FORMAT_MAGIC) {
            revert("invalid magic");
        }
        timestamp = _readBytes8(update, pos);
        pos += 8;
        channel = PythLazerStructs.Channel(_readBytes1(update, pos));
        pos += 1;
        feedsLen = uint8(_readBytes1(update, pos));
        pos += 1;
    }

    function parseFeedHeader(
        bytes memory update,
        uint16 pos
    )
        public
        pure
        returns (uint32 feed_id, uint8 num_properties, uint16 new_pos)
    {
        feed_id = _readBytes4(update, pos);
        pos += 4;
        num_properties = uint8(_readBytes1(update, pos));
        pos += 1;
        new_pos = pos;
    }

    function parseFeedProperty(
        bytes memory update,
        uint16 pos
    )
        public
        pure
        returns (PythLazerStructs.PriceFeedProperty property, uint16 new_pos)
    {
        uint8 propertyId = _readBytes1(update, pos);
        require(propertyId <= 12, "Unknown property");
        property = PythLazerStructs.PriceFeedProperty(propertyId);
        pos += 1;
        new_pos = pos;
    }

    function parseFeedValueUint64(
        bytes memory update,
        uint16 pos
    ) internal pure returns (uint64 value, uint16 new_pos) {
        value = _readBytes8(update, pos);
        pos += 8;
        new_pos = pos;
    }

    function parseFeedValueInt64(
        bytes memory update,
        uint16 pos
    ) internal pure returns (int64 value, uint16 new_pos) {
        value = int64(_readBytes8(update, pos));
        pos += 8;
        new_pos = pos;
    }

    function parseFeedValueUint16(
        bytes memory update,
        uint16 pos
    ) internal pure returns (uint16 value, uint16 new_pos) {
        value = _readBytes2(update, pos);
        pos += 2;
        new_pos = pos;
    }

    function parseFeedValueInt16(
        bytes memory update,
        uint16 pos
    ) internal pure returns (int16 value, uint16 new_pos) {
        value = int16(_readBytes2(update, pos));
        pos += 2;
        new_pos = pos;
    }

    function parseFeedValueUint8(
        bytes memory update,
        uint16 pos
    ) internal pure returns (uint8 value, uint16 new_pos) {
        value = _readBytes1(update, pos);
        pos += 1;
        new_pos = pos;
    }

    function parseUpdateFromPayload(
        bytes memory payload
    ) public pure returns (PythLazerStructs.Update memory update) {
        uint16 pos;
        uint8 feedsLen;
        (update.timestamp, update.channel, feedsLen, pos) = parsePayloadHeader(payload);

        update.feeds = new PythLazerStructs.Feed[](feedsLen);

        for (uint8 i = 0; i < feedsLen; i++) {
            PythLazerStructs.Feed memory feed;

            uint32 feedId;
            uint8 numProperties;
            (feedId, numProperties, pos) = parseFeedHeader(payload, pos);

            feed.feedId = feedId;
            feed.triStateMap = 0;

            for (uint8 j = 0; j < numProperties; j++) {
                PythLazerStructs.PriceFeedProperty property;
                (property, pos) = parseFeedProperty(payload, pos);

                if (property == PythLazerStructs.PriceFeedProperty.Price) {
                    (feed._price, pos) = parseFeedValueInt64(payload, pos);
                    if (feed._price != 0) {
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.Price));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.Price));
                    }
                } else if (property == PythLazerStructs.PriceFeedProperty.BestBidPrice) {
                    (feed._bestBidPrice, pos) = parseFeedValueInt64(payload, pos);
                    if (feed._bestBidPrice != 0) {
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.BestBidPrice));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.BestBidPrice));
                    }
                } else if (property == PythLazerStructs.PriceFeedProperty.BestAskPrice) {
                    (feed._bestAskPrice, pos) = parseFeedValueInt64(payload, pos);
                    if (feed._bestAskPrice != 0) {
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.BestAskPrice));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.BestAskPrice));
                    }
                } else if (property == PythLazerStructs.PriceFeedProperty.PublisherCount) {
                    (feed._publisherCount, pos) = parseFeedValueUint16(payload, pos);
                    if (feed._publisherCount != 0) {
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.PublisherCount));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.PublisherCount));
                    }
                } else if (property == PythLazerStructs.PriceFeedProperty.Exponent) {
                    (feed._exponent, pos) = parseFeedValueInt16(payload, pos);
                    _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.Exponent));
                } else if (property == PythLazerStructs.PriceFeedProperty.Confidence) {
                    (feed._confidence, pos) = parseFeedValueUint64(payload, pos);
                    if (feed._confidence != 0) {
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.Confidence));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.Confidence));
                    }
                } else if (property == PythLazerStructs.PriceFeedProperty.FundingRate) {
                    uint8 exists;
                    (exists, pos) = parseFeedValueUint8(payload, pos);
                    if (exists != 0) {
                        (feed._fundingRate, pos) = parseFeedValueInt64(payload, pos);
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.FundingRate));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.FundingRate));
                    }
                } else if (property == PythLazerStructs.PriceFeedProperty.FundingTimestamp) {
                    uint8 exists;
                    (exists, pos) = parseFeedValueUint8(payload, pos);
                    if (exists != 0) {
                        (feed._fundingTimestamp, pos) = parseFeedValueUint64(payload, pos);
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.FundingTimestamp));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.FundingTimestamp));
                    }
                } else if (property == PythLazerStructs.PriceFeedProperty.FundingRateInterval) {
                    uint8 exists;
                    (exists, pos) = parseFeedValueUint8(payload, pos);
                    if (exists != 0) {
                        (feed._fundingRateInterval, pos) = parseFeedValueUint64(payload, pos);
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.FundingRateInterval));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.FundingRateInterval));
                    }
                } else if (property == PythLazerStructs.PriceFeedProperty.MarketSession) {
                    int16 marketSessionValue;
                    (marketSessionValue, pos) = parseFeedValueInt16(payload, pos);
                    require(marketSessionValue >= 0 && marketSessionValue <= 4, "Invalid market session value");
                    feed._marketSession = PythLazerStructs.MarketSession(uint8(uint16(marketSessionValue)));
                    _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.MarketSession));
                } else if (property == PythLazerStructs.PriceFeedProperty.EmaPrice) {
                    (feed._emaPrice, pos) = parseFeedValueInt64(payload, pos);
                    if (feed._emaPrice != 0) {
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.EmaPrice));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.EmaPrice));
                    }
                } else if (property == PythLazerStructs.PriceFeedProperty.EmaConfidence) {
                    (feed._emaConfidence, pos) = parseFeedValueUint64(payload, pos);
                    if (feed._emaConfidence != 0) {
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.EmaConfidence));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.EmaConfidence));
                    }
                } else if (property == PythLazerStructs.PriceFeedProperty.FeedUpdateTimestamp) {
                    uint8 exists;
                    (exists, pos) = parseFeedValueUint8(payload, pos);
                    if (exists != 0) {
                        (feed._feedUpdateTimestamp, pos) = parseFeedValueUint64(payload, pos);
                        _setPresent(feed, uint8(PythLazerStructs.PriceFeedProperty.FeedUpdateTimestamp));
                    } else {
                        _setApplicableButMissing(feed, uint8(PythLazerStructs.PriceFeedProperty.FeedUpdateTimestamp));
                    }
                } else {
                    revert("Unexpected property");
                }
            }

            update.feeds[i] = feed;
        }

        require(pos == payload.length, "Payload has extra unknown bytes");
    }

    function hasPrice(PythLazerStructs.Feed memory feed) public pure returns (bool) {
        return _hasValue(feed, uint8(PythLazerStructs.PriceFeedProperty.Price));
    }

    function hasConfidence(PythLazerStructs.Feed memory feed) public pure returns (bool) {
        return _hasValue(feed, uint8(PythLazerStructs.PriceFeedProperty.Confidence));
    }

    function isPriceRequested(PythLazerStructs.Feed memory feed) public pure returns (bool) {
        return _isRequested(feed, uint8(PythLazerStructs.PriceFeedProperty.Price));
    }

    function isConfidenceRequested(PythLazerStructs.Feed memory feed) public pure returns (bool) {
        return _isRequested(feed, uint8(PythLazerStructs.PriceFeedProperty.Confidence));
    }

    function getPrice(PythLazerStructs.Feed memory feed) public pure returns (int64) {
        require(isPriceRequested(feed), "Price is not requested for the timestamp");
        require(hasPrice(feed), "Price is not present for the timestamp");
        return feed._price;
    }

    function getConfidence(PythLazerStructs.Feed memory feed) public pure returns (uint64) {
        require(isConfidenceRequested(feed), "Confidence is not requested for the timestamp");
        require(hasConfidence(feed), "Confidence is not present for the timestamp");
        return feed._confidence;
    }

    function getFeedId(PythLazerStructs.Feed memory feed) public pure returns (uint32) {
        return feed.feedId;
    }
}
