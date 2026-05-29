"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.KinshipModule = void 0;
const common_1 = require("@nestjs/common");
const kinship_controller_1 = require("./kinship.controller");
const kinship_service_1 = require("./kinship.service");
let KinshipModule = class KinshipModule {
};
exports.KinshipModule = KinshipModule;
exports.KinshipModule = KinshipModule = __decorate([
    (0, common_1.Module)({
        controllers: [kinship_controller_1.KinshipController],
        providers: [kinship_service_1.KinshipService],
        exports: [kinship_service_1.KinshipService],
    })
], KinshipModule);
//# sourceMappingURL=kinship.module.js.map