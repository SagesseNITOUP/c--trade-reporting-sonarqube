#pragma once

#include <string>

namespace reporting {

// Règles volontairement simplifiées pour un exercice pédagogique.
enum class AssetClass { Rates, FX, Credit, Unknown };

enum class ValidationCode {
    Valid,
    MissingUti,
    InvalidNotional,
    UnsupportedCurrency,
    UnsupportedAssetClass,
    InactiveCounterparty
};

struct Trade {
    std::string uti;
    double notional;
    std::string currency;
    AssetClass assetClass;
    bool counterpartyActive;
};

struct ValidationResult {
    ValidationCode code;
    std::string message;
};

ValidationResult validateTrade(const Trade& trade);

}  // namespace reporting
