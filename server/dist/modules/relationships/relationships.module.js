"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.RelationshipsModule = void 0;
const common_1 = require("@nestjs/common");
const relationships_controller_1 = require("./relationships.controller");
const relationships_service_1 = require("./relationships.service");
const gateway_module_1 = require("../gateway/gateway.module");
let RelationshipsModule = class RelationshipsModule {
};
exports.RelationshipsModule = RelationshipsModule;
exports.RelationshipsModule = RelationshipsModule = __decorate([
    (0, common_1.Module)({
        imports: [gateway_module_1.GatewayModule],
        controllers: [relationships_controller_1.RelationshipsController],
        providers: [relationships_service_1.RelationshipsService],
        exports: [relationships_service_1.RelationshipsService],
    })
], RelationshipsModule);
//# sourceMappingURL=relationships.module.js.map