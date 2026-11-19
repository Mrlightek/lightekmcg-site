const {check}=require('./studio_mechanics_test.cjs');
(async()=>{for(const dashboard of [false,true])for(const restore of [false,true])await check(dashboard,restore,'grasp');})().catch(error=>{console.error(error);process.exitCode=1;});
