#include "trade_validator.hpp"

#include <cmath>

namespace reporting {

namespace {
bool isSupportedCurrency(const std::string& currency) {
    return currency == "EUR" || currency == "USD" || currency == "GBP";
}
}  // namespace

ValidationResult validateTrade(const Trade& trade) {
    if (trade.uti.empty()) {
        return {ValidationCode::MissingUti, "UTI manquant"};
    }

    if (!std::isfinite(trade.notional) || trade.notional <= 0.0) {
        return {ValidationCode::InvalidNotional, "Montant notionnel invalide"};
    }

    if (!isSupportedCurrency(trade.currency)) {
        return {ValidationCode::UnsupportedCurrency, "Devise non supportee"};
    }

    if (trade.assetClass == AssetClass::Unknown) {
        return {ValidationCode::UnsupportedAssetClass, "Classe d'actifs non supportee"};
    }

    if (!trade.counterpartyActive) {
        return {ValidationCode::InactiveCounterparty, "Contrepartie inactive"};
    }

    return {ValidationCode::Valid, "Transaction valide"};
}

}  // namespace reporting
