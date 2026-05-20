#pragma once

#include <string>
#include <map>
#include <vector>
#include <cstdint>

namespace prometheus {

class Registry;

namespace simpleapi {
extern Registry& registry;
}

template<typename T>
class Histogram {
public:
    Histogram() = default;
    void Observe(T) {}
};

template<typename T>
class CustomFamily {
public:
    CustomFamily(const std::string&, const std::string&) {}
    T& Add(const std::map<std::string, std::string>&, const std::vector<T>& = {}) { static T dummy; return dummy; }
};

template<typename T>
class Builder {
public:
    Builder& Name(const std::string&) { return *this; }
    Builder& Help(const std::string&) { return *this; }
    CustomFamily<T>& Register(Registry&) { static CustomFamily<T> dummy("", ""); return dummy; }
};

} // namespace prometheus
