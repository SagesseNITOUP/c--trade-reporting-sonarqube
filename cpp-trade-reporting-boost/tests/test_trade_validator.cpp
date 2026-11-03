#define BOOST_TEST_MODULE TradeValidatorTests
#include <boost/test/included/unit_test.hpp>

#include "trade_validator.hpp"

#include <limits>

using reporting::AssetClass;
using reporting::Trade;
using reporting::ValidationCode;
using reporting::validateTrade;

namespace {
Trade validTrade() {
    return {"UTI-2026-0001", 1250000.0, "EUR", AssetClass::Rates, true};
}

void expectCode(const Trade& trade, ValidationCode expected) {
    const auto result = validateTrade(trade);
    BOOST_TEST(static_cast<int>(result.code) == static_cast<int>(expected));
    BOOST_TEST(!result.message.empty());
}
}  // namespace

BOOST_AUTO_TEST_CASE(TransactionValideEnEUR) {
    expectCode(validTrade(), ValidationCode::Valid);
}

BOOST_AUTO_TEST_CASE(TransactionValideEnUSD) {
    auto trade = validTrade();
    trade.currency = "USD";
    trade.assetClass = AssetClass::FX;
    expectCode(trade, ValidationCode::Valid);
}

BOOST_AUTO_TEST_CASE(TransactionValideEnGBP) {
    auto trade = validTrade();
    trade.currency = "GBP";
    trade.assetClass = AssetClass::Credit;
    expectCode(trade, ValidationCode::Valid);
}

BOOST_AUTO_TEST_CASE(UtiManquant) {
    auto trade = validTrade();
    trade.uti.clear();
    expectCode(trade, ValidationCode::MissingUti);
}

BOOST_AUTO_TEST_CASE(MontantNul) {
    auto trade = validTrade();
    trade.notional = 0.0;
    expectCode(trade, ValidationCode::InvalidNotional);
}

BOOST_AUTO_TEST_CASE(MontantNegatif) {
    auto trade = validTrade();
    trade.notional = -50.0;
    expectCode(trade, ValidationCode::InvalidNotional);
}

BOOST_AUTO_TEST_CASE(MontantInfini) {
    auto trade = validTrade();
    trade.notional = std::numeric_limits<double>::infinity();
    expectCode(trade, ValidationCode::InvalidNotional);
}

BOOST_AUTO_TEST_CASE(MontantNaN) {
    auto trade = validTrade();
    trade.notional = std::numeric_limits<double>::quiet_NaN();
    expectCode(trade, ValidationCode::InvalidNotional);
}

BOOST_AUTO_TEST_CASE(DeviseNonSupportee) {
    auto trade = validTrade();
    trade.currency = "JPY";
    expectCode(trade, ValidationCode::UnsupportedCurrency);
}

BOOST_AUTO_TEST_CASE(CategorieNonSupportee) {
    auto trade = validTrade();
    trade.assetClass = AssetClass::Unknown;
    expectCode(trade, ValidationCode::UnsupportedAssetClass);
}

BOOST_AUTO_TEST_CASE(ContrepartieInactive) {
    auto trade = validTrade();
    trade.counterpartyActive = false;
    expectCode(trade, ValidationCode::InactiveCounterparty);
}

BOOST_AUTO_TEST_CASE(PrioriteDeLaValidation) {
    auto trade = validTrade();
    trade.uti = "";
    trade.currency = "JPY";
    expectCode(trade, ValidationCode::MissingUti);
}
