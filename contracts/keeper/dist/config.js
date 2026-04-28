"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.config = void 0;
const dotenv = __importStar(require("dotenv"));
dotenv.config();
exports.config = {
    rpcUrl: process.env.HYPEREVM_RPC_URL,
    keeperPrivateKey: process.env.KEEPER_PRIVATE_KEY,
    chainId: parseInt(process.env.CHAIN_ID || '998'),
    contracts: {
        signalRegistry: process.env.SIGNAL_REGISTRY_ADDRESS,
        epochScoring: process.env.EPOCH_SCORING_ADDRESS,
        zentStaking: process.env.ZENT_STAKING_ADDRESS,
        zentToken: process.env.ZENT_TOKEN_ADDRESS,
    },
    supabase: {
        url: process.env.SUPABASE_URL,
        serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    },
    scoringOracle: process.env.SCORING_ORACLE_ADDRESS,
};
// Validate required env vars
const required = [
    'HYPEREVM_RPC_URL',
    'KEEPER_PRIVATE_KEY',
    'SIGNAL_REGISTRY_ADDRESS',
    'EPOCH_SCORING_ADDRESS',
    'SUPABASE_URL',
    'SUPABASE_SERVICE_ROLE_KEY',
];
for (const key of required) {
    if (!process.env[key]) {
        throw new Error(`Missing required env var: ${key}`);
    }
}
