// Define types
public type Token = {
    symbol: Text;
};

public type PriceData = {
    price: Float;  // Price with 18 decimals
    timestamp: Int;
    lastUpdate: Int;
};

public type PortfolioValue = {
    totalValue: Float;  // Value with 18 decimals
    holdings: [(Text, Float, Float)]; // (Symbol, Amount with 18 decimals, Value with 18 decimals)
};

public type AddPriceResult = {
    #Ok: PriceData;
    #Err: Text;
};

// Initialize state
private stable var priceEntries : [(Text, PriceData)] = [];
private stable var balanceEntries : [(Principal, [(Token, Float)])] = [];

private let userBalances = HashMap.HashMap<Principal, [(Token, Float)]>(
    10, Principal.equal, Principal.hash
);

private let tokenPrices = HashMap.HashMap<Text, PriceData>(
    10, Text.equal, Text.hash
);

// System upgrade hooks
system func preupgrade() {
    priceEntries := Iter.toArray(tokenPrices.entries());
    balanceEntries := Iter.toArray(userBalances.entries());
};

system func postupgrade() {
    for ((symbol, price) in priceEntries.vals()) {
        tokenPrices.put(symbol, price);
    };
    for ((principal, balances) in balanceEntries.vals()) {
        userBalances.put(principal, balances);
    };
};

// Helper function to format display values
private func formatDecimal(value: Float) : Float {
    value / DECIMAL_FACTOR;
};

// Helper function to convert input to internal representation
private func toInternalValue(value: Float) : Float {
    value * DECIMAL_FACTOR;
};

// Add new token price with validation
public shared(msg) func addTokenPrice(symbol: Text, initialPrice: Float) : async AddPriceResult {
    if (Text.size(symbol) == 0) {
        return #Err("Symbol cannot be empty");
    };

    if (initialPrice <= 0) {
        return #Err("Price must be greater than 0");
    };

    let currentTime = Time.now();
    let newPriceData : PriceData = {
        price = toInternalValue(initialPrice);
        timestamp = currentTime;
        lastUpdate = currentTime;
    };

    tokenPrices.put(symbol, newPriceData);
    #Ok(newPriceData);
};

// Update balance for a user
public shared(msg) func updateBalance(token: Token, amount: Float) : async Result.Result<(), Text> {
    if (amount < 0) {
        return #err("Amount cannot be negative");
    };

    let caller = msg.caller;
    let internalAmount = toInternalValue(amount);
    
    switch (userBalances.get(caller)) {
        case null {
            userBalances.put(caller, [(token, internalAmount)]);
        };
        case (?existing) {
            var found = false;
            let newBalances = Array.map<(Token, Float), (Token, Float)>(
                existing,
                func((t, bal)) : (Token, Float) {
                    if (t.symbol == token.symbol) {
                        found := true;
                        return (t, internalAmount);
                    };
                    return (t, bal);
                }
            );
            
            if (not found) {
                let newArray = Array.append<(Token, Float)>(newBalances, [(token, internalAmount)]);
                userBalances.put(caller, newArray);
            } else {
                userBalances.put(caller, newBalances);
            };
        };
    };
    #ok(());
};

// Update token price
public shared(msg) func updatePrice(symbol: Text, price: Float) : async Result.Result<(), Text> {
    if (price <= 0) {
        return #err("Price must be greater than 0");
    };

    switch (tokenPrices.get(symbol)) {
        case null {
            return #err("Token not found. Please add token first using addTokenPrice");
        };
        case (?existingPrice) {
            tokenPrices.put(symbol, {
                price = toInternalValue(price);
                timestamp = Time.now();
                lastUpdate = existingPrice.lastUpdate;
            });
            #ok(());
        };
    };
};

// Get portfolio value
public query(msg) func getPortfolioValue() : async PortfolioValue {
    let caller = msg.caller;
    
    switch (userBalances.get(caller)) {
        case null { return { totalValue = 0; holdings = []; }; };
        case (?balances) {
            var total : Float = 0;
            var holdings : [(Text, Float, Float)] = [];
            
            for ((token, amount) in Array.vals(balances)) {
                switch (tokenPrices.get(token.symbol)) {
                    case null { };
                    case (?priceData) {
                        let value = amount * priceData.price / DECIMAL_FACTOR;
                        total += value;
                        holdings := Array.append(holdings, [(
                            token.symbol, 
                            formatDecimal(amount), 
                            formatDecimal(value)
                        )]);
                    };
                };
            };
            
            return {
                totalValue = formatDecimal(total);
                holdings = holdings;
            };
        };
    };
};

// Get user balances
public query(msg) func getBalances() : async [(Token, Float)] {
    switch (userBalances.get(msg.caller)) {
        case null { []; };
        case (?balances) { 
            Array.map<(Token, Float), (Token, Float)>(
                balances,
                func((token, amount)) : (Token, Float) {
                    (token, formatDecimal(amount))
                }
            )
        };
    };
};

// Get token price with error handling
public query func getTokenPrice(symbol: Text) : async Result.Result<Float, Text> {
    switch (tokenPrices.get(symbol)) {
        case null { #err("Token price not found"); };
        case (?priceData) { #ok(formatDecimal(priceData.price)); };
    };
};

// Get all token prices
public query func getAllTokenPrices() : async [(Text, Float)] {
    Array.map<(Text, PriceData), (Text, Float)>(
        Iter.toArray(tokenPrices.entries()),
        func((symbol, priceData)) : (Text, Float) {
            (symbol, formatDecimal(priceData.price))
        }
    );
};