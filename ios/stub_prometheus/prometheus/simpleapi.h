#pragma once

#include <string>
#include <map>
#include <vector>
#include <chrono>
#include <memory>
#include <cstdint>
#include <thread>
#include <functional>
#include <fstream>
#include <iostream>

namespace prometheus {

class Registry {};

namespace simpleapi {

extern std::shared_ptr<Registry> registry_ptr;
extern Registry& registry;

class counter_metric_t {
public:
    counter_metric_t() = default;
    counter_metric_t(const std::string&, const std::string&) {}
    void operator++() {}
    void operator++(int) {}
    void operator+=(uint64_t) {}
    uint64_t value() const { return 0; }
};

class gauge_metric_t {
public:
    gauge_metric_t() = default;
    gauge_metric_t(const std::string&, const std::string&) {}
    void operator++() {}
    void operator++(int) {}
    void operator+=(int64_t) {}
    void operator--() {}
    void operator--(int) {}
    void operator-=(int64_t) {}
    void operator=(int64_t) {}
    int64_t value() const { return 0; }
};

template<typename T>
class family_wrapper_t {
public:
    family_wrapper_t(const std::string&, const std::string&) {}
    T Add(const std::map<std::string, std::string>&) { return T(); }
};

using counter_family_t = family_wrapper_t<counter_metric_t>;
using gauge_family_t = family_wrapper_t<gauge_metric_t>;

class SaveToFile {
public:
    SaveToFile() = default;
    SaveToFile(std::shared_ptr<Registry>&, const std::chrono::seconds&, const std::string&) {}
    void stop() {}
    void restart() {}
    void set_delay(const std::chrono::seconds&) {}
    bool set_out_file(const std::string&) { return true; }
    void set_registry(std::shared_ptr<Registry>&) {}
};

} // namespace simpleapi

} // namespace prometheus
