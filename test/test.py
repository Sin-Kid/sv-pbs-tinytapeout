# SPDX-FileCopyrightText: © 2026 Pavan G, Manali Kulkarni, Shylashree N, RV College of Engineering
# SPDX-License-Identifier: Apache-2.0
#
# cocotb tests for SV-PBS (tt_um_rvce_sv_pbs).
# Only top-level pins are used, so the same tests run on the RTL and on the
# gate-level netlist produced by the GDS flow.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

# Pin helpers ---------------------------------------------------------------
STROBE = 0x01  # uio_in[0]
COMMIT = 0x02  # uio_in[1]

NORMAL, WARNING, CRITICAL, SENSOR_DEGRADED = 0, 1, 2, 3


def outputs(dut):
    uo = int(dut.uo_out.value)
    uio = int(dut.uio_out.value)
    return {
        "state": uo & 0x3,
        "derate": (uo >> 2) & 1,
        "isolate": (uo >> 3) & 1,
        "degraded": (uo >> 4) & 1,
        "risk": (uo >> 5) & 1,
        "warning": (uo >> 6) & 1,
        "critical": (uo >> 7) & 1,
        "fault": (uio >> 2) & 0x7,
        "busy": (uio >> 7) & 1,
    }


async def reset(dut):
    clock = Clock(dut.clk, 100, unit="ns")  # 10 MHz
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def send_sample(dut, voltage_mv, current_ma, temp_dc):
    """Send one sample (voltage in mV, current in mA, temperature in 0.1 degC)."""
    data = [
        (voltage_mv >> 8) & 0xFF, voltage_mv & 0xFF,
        (current_ma >> 8) & 0xFF, current_ma & 0xFF,
        (temp_dc >> 4) & 0xFF, temp_dc & 0x0F,
    ]
    for byte in data:
        await FallingEdge(dut.clk)
        dut.ui_in.value = byte
        dut.uio_in.value = STROBE
        await FallingEdge(dut.clk)
        dut.uio_in.value = 0
    await FallingEdge(dut.clk)
    dut.uio_in.value = COMMIT
    await FallingEdge(dut.clk)
    dut.uio_in.value = 0
    # Wait for processing to finish (busy = uio_out[7])
    await FallingEdge(dut.clk)
    for _ in range(200):
        if outputs(dut)["busy"] == 0:
            break
        await FallingEdge(dut.clk)
    else:
        raise AssertionError("busy did not clear")
    return outputs(dut)


@cocotb.test()
async def test_reset_and_pin_directions(dut):
    await reset(dut)
    assert int(dut.uio_oe.value) == 0x9C, "uio[1:0],[6:5] inputs; uio[4:2],[7] outputs"
    o = outputs(dut)
    assert o["state"] == NORMAL and o["isolate"] == 0 and o["derate"] == 0
    assert o["busy"] == 0


@cocotb.test()
async def test_nominal_operation(dut):
    await reset(dut)
    for _ in range(6):
        o = await send_sample(dut, 3700, 200, 300)
    dut._log.info(f"nominal: {o}")
    assert o["state"] == NORMAL
    assert o["isolate"] == 0 and o["derate"] == 0
    assert o["warning"] == 0 and o["critical"] == 0
    assert o["degraded"] == 0 and o["fault"] == 0 and o["risk"] == 0


@cocotb.test()
async def test_over_temperature_isolates(dut):
    await reset(dut)
    for _ in range(4):
        await send_sample(dut, 3700, 200, 300)
    for _ in range(4):
        o = await send_sample(dut, 3700, 200, 550)  # 55.0 degC
    dut._log.info(f"over-temperature: {o}")
    assert o["state"] == CRITICAL and o["isolate"] == 1 and o["derate"] == 1
    assert o["critical"] == 1 and o["warning"] == 0


@cocotb.test()
async def test_over_voltage_isolates(dut):
    await reset(dut)
    for _ in range(4):
        await send_sample(dut, 3700, 200, 300)
    for _ in range(4):
        o = await send_sample(dut, 4700, 200, 300)  # 4.7 V
    assert o["state"] == CRITICAL and o["isolate"] == 1


@cocotb.test()
async def test_over_current_warning_then_critical(dut):
    await reset(dut)
    for _ in range(4):
        await send_sample(dut, 3700, 200, 300)
    for _ in range(4):
        o = await send_sample(dut, 3700, 500, 300)   # 0.5 A: derate only
    assert o["state"] == WARNING and o["derate"] == 1 and o["isolate"] == 0
    assert o["warning"] == 1 and o["critical"] == 0
    for _ in range(4):
        o = await send_sample(dut, 3700, 1100, 300)  # 1.1 A: isolate
    assert o["state"] == CRITICAL and o["isolate"] == 1


@cocotb.test()
async def test_stuck_sensor_degrades_without_isolation(dut):
    """Voltage reading frozen while current keeps changing: sensor fault,
    battery is derated but NOT disconnected."""
    await reset(dut)
    seen_degraded = False
    for k in range(16):
        o = await send_sample(dut, 3700, 100 + 7 * k, 300 + 3 * k)
        assert o["isolate"] == 0, "a sensor fault alone must not isolate the battery"
        if o["degraded"]:
            seen_degraded = True
            assert o["fault"] == 4, f"expected fault code 4 (voltage stuck), got {o['fault']}"
    assert seen_degraded
    assert o["state"] == SENSOR_DEGRADED and o["derate"] == 1


@cocotb.test()
async def test_thermal_trend_predicts_before_limit(dut):
    """A steady temperature rise is flagged before the 50.0 degC hard limit."""
    await reset(dut)
    first_risk = first_isolate = None
    for k in range(50):  # 30.0 degC rising 0.5 degC per sample
        o = await send_sample(dut, 3700, 200, 300 + 5 * k)
        if o["risk"] and first_risk is None:
            first_risk = k
        if o["isolate"] and first_isolate is None:
            first_isolate = k
    dut._log.info(f"risk first at sample {first_risk}, isolation at sample {first_isolate}")
    assert first_risk is not None and first_isolate is not None
    assert first_risk < first_isolate


@cocotb.test()
async def test_recovery_needs_consecutive_safe_samples(dut):
    await reset(dut)
    for _ in range(4):
        await send_sample(dut, 3700, 200, 300)
    for _ in range(4):
        o = await send_sample(dut, 3700, 200, 550)
    assert o["state"] == CRITICAL
    states = []
    for _ in range(10):
        o = await send_sample(dut, 3700, 200, 300)
        states.append(o["state"])
    dut._log.info(f"recovery states: {states}")
    assert states[0] != NORMAL, "must not release isolation immediately"
    assert states[-1] == NORMAL and o["isolate"] == 0


@cocotb.test()
async def test_busy_ignores_input(dut):
    await reset(dut)
    await send_sample(dut, 3700, 200, 300)
    # Start a sample, then hammer the strobe while busy: it must be ignored
    for byte in [0x0E, 0x74, 0x00, 0xC8, 0x12, 0x0C]:
        await FallingEdge(dut.clk)
        dut.ui_in.value = byte
        dut.uio_in.value = STROBE
        await FallingEdge(dut.clk)
        dut.uio_in.value = 0
    await FallingEdge(dut.clk)
    dut.uio_in.value = COMMIT
    await FallingEdge(dut.clk)
    dut.uio_in.value = STROBE  # ignored while busy
    dut.ui_in.value = 0xFF
    await ClockCycles(dut.clk, 5)
    assert outputs(dut)["busy"] == 1
    dut.uio_in.value = 0
    for _ in range(100):
        await FallingEdge(dut.clk)
        if outputs(dut)["busy"] == 0:
            break
    assert outputs(dut)["busy"] == 0
    # The next full sample must still be accepted and give a normal result
    for _ in range(3):
        o = await send_sample(dut, 3700, 200, 300)
    assert o["state"] == NORMAL and o["isolate"] == 0


@cocotb.test()
async def test_out_of_range_is_clipped(dut):
    """Readings above full scale (here 65.535 V) are clipped and flagged."""
    await reset(dut)
    for _ in range(4):
        await send_sample(dut, 3700, 200, 300)
    for _ in range(4):
        o = await send_sample(dut, 0xFFFF, 200, 300)
    assert o["state"] == CRITICAL and o["isolate"] == 1
    assert o["degraded"] == 1 and o["fault"] == 1   # voltage out of sensor range
